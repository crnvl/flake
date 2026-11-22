use super::*;
use axum::routing::delete;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

#[derive(Clone)]
struct Fake {
    posts: Arc<AtomicUsize>,
    deletes: Arc<AtomicUsize>,
    lost_reply: Arc<AtomicBool>,
    delete_failure: Arc<AtomicBool>,
    pod_exists: Arc<AtomicBool>,
    creation: Arc<Mutex<Value>>,
    completion: Arc<Mutex<Value>>,
    catalog: Arc<Mutex<Value>>,
}
struct Fixture {
    _tmp: tempfile::TempDir,
    task: tokio::task::JoinHandle<()>,
    controller: Controller,
    fake: Fake,
    clock: Arc<AtomicU64>,
    base: String,
}
impl Drop for Fixture {
    fn drop(&mut self) {
        self.task.abort();
    }
}
async fn fixture() -> Fixture {
    let fake = Fake {
        posts: Arc::new(AtomicUsize::new(0)),
        deletes: Arc::new(AtomicUsize::new(0)),
        lost_reply: Arc::new(AtomicBool::new(false)),
        delete_failure: Arc::new(AtomicBool::new(false)),
        pod_exists: Arc::new(AtomicBool::new(false)),
        creation: Arc::new(Mutex::new(Value::Null)),
        completion: Arc::new(Mutex::new(Value::Null)),
        catalog: Arc::new(Mutex::new(json!({"gpus":[
            {"id":api::GPU,"secure":true,"availability":"LOW","price":{"secure":0.27}},
            {"id":"NVIDIA A40","secure":true,"availability":"HIGH","price":{"secure":0.59}}
        ]}))),
    };
    let router = Router::new()
        .route("/catalog/gpus", get(|ExtractState(fake):ExtractState<Fake>,axum::extract::Query(query):axum::extract::Query<std::collections::HashMap<String,String>>| async move {
            assert_eq!(query.get("include").unwrap(),"AVAILABILITY");assert_eq!(query.get("cloud").unwrap(),"SECURE");
            Json(fake.catalog.lock().await.clone())
        }))
        .route("/pods", post(|ExtractState(fake):ExtractState<Fake>,Json(body):Json<Value>| async move {
            assert!(!fake.pod_exists.swap(true, Ordering::SeqCst), "replacement requested before previous Pod deletion");
            fake.posts.fetch_add(1,Ordering::SeqCst);
            let gpu = body["gpu"]["id"].clone();
            let cost = if gpu == "NVIDIA A40" { 0.59 } else { 0.27 };
            *fake.creation.lock().await=body;
            if fake.lost_reply.load(Ordering::SeqCst) { StatusCode::BAD_GATEWAY.into_response() }
            else { Json(json!({"id":"testpod123","cost":cost,"cloud":"SECURE","gpu":{"id":gpu,"count":1}})).into_response() }
        }).get(|ExtractState(fake):ExtractState<Fake>| async move {
            let body=fake.creation.lock().await;Json(json!({"pods":[{"id":"testpod123","name":body["name"]}],"pagination":{"hasNextPage":false}}))
        }))
        .route("/pods/testpod123",delete(|ExtractState(fake):ExtractState<Fake>|async move {
            fake.deletes.fetch_add(1,Ordering::SeqCst);
            if fake.delete_failure.load(Ordering::SeqCst) { StatusCode::BAD_GATEWAY } else {
                fake.pod_exists.store(false, Ordering::SeqCst);
                StatusCode::NO_CONTENT
            }
        }))
        .route("/v1/models",get(||async {Json(json!({"data":[{"id":"qwen3.6-35b-a3b-uncensored"}]}))}))
        .route("/v1/chat/completions",post(|ExtractState(fake):ExtractState<Fake>,Json(body):Json<Value>|async move {
            *fake.completion.lock().await=body;
            ([(header::CONTENT_TYPE,"text/event-stream")],"data: {\"choices\":[{\"delta\":{\"content\":\"mock reply\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n")
        })).with_state(fake.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}/", listener.local_addr().unwrap());
    let task = tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    let mut api = api::Api::new("test-key".into()).unwrap();
    api.base = base.clone();
    let tmp = tempfile::tempdir().unwrap();
    let clock = Arc::new(AtomicU64::new(1795352000));
    let mut controller = Controller::new(tmp.path().into(), Some(api)).unwrap();
    let c = clock.clone();
    controller.clock = Arc::new(move || c.load(Ordering::SeqCst) as f64);
    Fixture {
        _tmp: tmp,
        task,
        controller,
        fake,
        clock,
        base,
    }
}

#[tokio::test]
async fn paused_by_default_and_status_is_free() {
    let f = fixture().await;
    assert_eq!(f.controller.status().unwrap()["paused"], true);
    assert_eq!(
        f.controller.ensure().await.err().unwrap().status,
        StatusCode::FORBIDDEN
    );
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn on_demand_startup_arms_without_credentials_or_allocation() {
    let f = fixture().await;
    let mut controller = f.controller.clone();
    controller.api = None; // initialization must not even need the Runpod API
    controller.initialize_on_demand().await.unwrap();
    let state = controller.read().unwrap();
    assert!(!state.paused);
    assert!(state.on_demand_initialized);
    assert!(state.lease.is_none());
    assert!(state.history.is_empty());
    assert_eq!(controller.status().unwrap()["pod"], Value::Null);
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn on_demand_migration_preserves_legacy_lease_and_budget() {
    let f = fixture().await;
    f.controller.resume().await.unwrap();
    f.controller.ensure().await.unwrap();
    let mut legacy = serde_json::to_value(f.controller.read().unwrap()).unwrap();
    legacy
        .as_object_mut()
        .unwrap()
        .remove("on_demand_initialized");
    legacy["paused"] = json!(true);
    legacy["history"] = json!([[1795351800.0, 1795351900.0]]);
    fs::write(f._tmp.path().join("state.json"), legacy.to_string()).unwrap();
    let mut restarted = f.controller.clone();
    restarted.api = None;
    restarted.initialize_on_demand().await.unwrap();
    let migrated = serde_json::to_value(restarted.read().unwrap()).unwrap();
    assert_eq!(migrated["lease"], legacy["lease"]);
    assert_eq!(migrated["history"], legacy["history"]);
    assert_eq!(migrated["paused"], false);
    let before = fs::read(f._tmp.path().join("state.json")).unwrap();
    restarted.initialize_on_demand().await.unwrap();
    assert_eq!(fs::read(f._tmp.path().join("state.json")).unwrap(), before);
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 1);
    assert_eq!(f.fake.deletes.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn explicit_pause_before_initialization_survives_restarts() {
    let f = fixture().await;
    f.controller.pause().await.unwrap();
    f.controller.initialize_on_demand().await.unwrap();
    assert!(f.controller.read().unwrap().paused);
    assert_eq!(
        f.controller.ensure().await.err().unwrap().status,
        StatusCode::FORBIDDEN
    );
    f.controller.resume().await.unwrap();
    f.controller.initialize_on_demand().await.unwrap();
    assert!(!f.controller.read().unwrap().paused);
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn on_demand_migration_cannot_reset_exhausted_monthly_allowance() {
    let f = fixture().await;
    let mut state = f.controller.read().unwrap();
    let t = (f.controller.clock)();
    state.history = vec![[t - 21600.0, t]];
    f.controller.save(&state).unwrap();
    f.controller.initialize_on_demand().await.unwrap();
    assert!(f.controller.ensure().await.is_err());
    assert_eq!(f.controller.read().unwrap().history, state.history);
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn prefers_a5000_then_selects_a40_and_rejects_over_budget() {
    let f = fixture().await;
    f.controller.resume().await.unwrap();
    let first = f.controller.ensure().await.unwrap();
    assert_eq!(first.gpu, api::GPU);
    f.controller.pause().await.unwrap();
    f.fake.catalog.lock().await["gpus"][0]["availability"] = json!("NONE");
    f.controller.resume().await.unwrap();
    let fallback = f.controller.ensure().await.unwrap();
    assert_eq!(fallback.gpu, "NVIDIA A40");
    assert_eq!(fallback.rate, Some(0.59));
    assert_eq!(f.controller.status().unwrap()["gpu"], "NVIDIA A40");
    assert_eq!(f.fake.creation.lock().await["gpu"]["id"], "NVIDIA A40");
    f.controller.pause().await.unwrap();
    f.fake.catalog.lock().await["gpus"][1]["price"]["secure"] = json!(0.61);
    f.controller.resume().await.unwrap();
    assert!(f.controller.ensure().await.is_err());
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 2);
}
#[tokio::test]
async fn concurrent_requests_create_one_pod_and_idle_waits_for_active_users() {
    let f = fixture().await;
    f.controller.resume().await.unwrap();
    let (a, b) = tokio::join!(f.controller.ensure(), f.controller.ensure());
    let a = a.unwrap();
    assert_eq!(a.id, b.unwrap().id);
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 1);
    f.controller.touch(&a.name, true).await.unwrap();
    f.clock.fetch_add(300, Ordering::SeqCst);
    let active = f.controller.active().unwrap();
    f.controller.reap(None).await.unwrap();
    assert_eq!(f.fake.deletes.load(Ordering::SeqCst), 0);
    f.controller.touch(&a.name, false).await.unwrap();
    drop(active);
    f.clock.fetch_add(119, Ordering::SeqCst);
    f.controller.reap(None).await.unwrap();
    assert_eq!(f.fake.deletes.load(Ordering::SeqCst), 0);
    f.clock.fetch_add(1, Ordering::SeqCst);
    f.controller.reap(None).await.unwrap();
    assert!(f.controller.read().unwrap().lease.is_none());
}

#[tokio::test]
async fn expired_pod_is_deleted_before_concurrent_requests_renew_the_lease() {
    let f = fixture().await;
    f.controller.initialize_on_demand().await.unwrap();
    let first = f.controller.ensure().await.unwrap();
    f.clock.fetch_add(1801, Ordering::SeqCst);
    let (a, b) = tokio::join!(f.controller.ensure(), f.controller.ensure());
    let a = a.unwrap();
    assert_ne!(first.name, a.name);
    assert_eq!(a.name, b.unwrap().name);
    assert_eq!(f.fake.deletes.load(Ordering::SeqCst), 1);
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 2);
    assert_eq!(
        f.controller.read().unwrap().history,
        vec![[first.start, (f.controller.clock)()]]
    );
    assert_eq!(a.deadline - a.start, state::LIFETIME);
}

#[tokio::test]
async fn failed_expiry_cleanup_blocks_replacement_until_delete_is_confirmed() {
    let f = fixture().await;
    f.controller.initialize_on_demand().await.unwrap();
    f.controller.ensure().await.unwrap();
    f.clock.fetch_add(1801, Ordering::SeqCst);
    f.fake.delete_failure.store(true, Ordering::SeqCst);
    assert!(f.controller.ensure().await.is_err());
    let state = f.controller.read().unwrap();
    assert!(state.lease.unwrap().closing);
    assert!(state.history.is_empty());
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 1);
    f.fake.delete_failure.store(false, Ordering::SeqCst);
    assert!(f.controller.ensure().await.is_ok());
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 2);
    assert_eq!(f.controller.read().unwrap().history.len(), 1);
}

#[tokio::test]
async fn expiry_cleanup_accounts_for_old_pod_before_checking_monthly_budget() {
    let f = fixture().await;
    f.controller.initialize_on_demand().await.unwrap();
    let t = (f.controller.clock)();
    let mut state = f.controller.read().unwrap();
    state.history = vec![[t - 19800.0, t]]; // only one 30-minute lease left
    f.controller.save(&state).unwrap();
    f.controller.ensure().await.unwrap();
    f.clock.fetch_add(1801, Ordering::SeqCst);
    assert!(f.controller.ensure().await.is_err());
    let state = f.controller.read().unwrap();
    assert!(state.lease.is_none());
    assert_eq!(state.history.len(), 2);
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 1);
    assert_eq!(f.fake.deletes.load(Ordering::SeqCst), 1);
}
#[tokio::test]
async fn ambiguous_create_survives_restart_and_cannot_duplicate() {
    let f = fixture().await;
    f.fake.lost_reply.store(true, Ordering::SeqCst);
    f.controller.resume().await.unwrap();
    assert!(f.controller.ensure().await.is_err());
    let restarted = Controller {
        ..f.controller.clone()
    };
    assert!(restarted.ensure().await.is_err());
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 1);
    f.clock.fetch_add(1801, Ordering::SeqCst);
    assert!(restarted.ensure().await.is_err()); // even expiry cannot duplicate an uncertain create
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 1);
    f.clock.fetch_add(121, Ordering::SeqCst);
    restarted.reap(None).await.unwrap();
    assert!(restarted.read().unwrap().lease.is_none());
    assert_eq!(f.fake.deletes.load(Ordering::SeqCst), 1);
}
#[tokio::test]
async fn pause_is_persistent_even_when_delete_fails() {
    let f = fixture().await;
    f.controller.resume().await.unwrap();
    f.controller.ensure().await.unwrap();
    f.fake.delete_failure.store(true, Ordering::SeqCst);
    assert!(f.controller.pause().await.is_err());
    f.controller.initialize_on_demand().await.unwrap();
    assert!(f.controller.read().unwrap().paused);
    assert!(f.controller.resume().await.is_err());
    f.fake.delete_failure.store(false, Ordering::SeqCst);
    f.controller.reap(None).await.unwrap();
    f.controller.initialize_on_demand().await.unwrap();
    assert_eq!(
        f.controller.ensure().await.err().unwrap().status,
        StatusCode::FORBIDDEN
    );
}
#[tokio::test]
async fn hard_deadline_overrides_active_stream_and_monthly_budget_blocks() {
    let f = fixture().await;
    f.controller.resume().await.unwrap();
    let lease = f.controller.ensure().await.unwrap();
    let _active = f.controller.active().unwrap();
    f.clock.fetch_add(1801, Ordering::SeqCst);
    f.controller.reap(None).await.unwrap();
    let mut s = f.controller.read().unwrap();
    assert_eq!(s.history[0][0], lease.start);
    assert!(s.lease.is_none());
    let t = (f.controller.clock)();
    s.history = vec![[t - 21600.0, t]];
    f.controller.save(&s).unwrap();
    assert!(f.controller.ensure().await.is_err());
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 1);
}
#[test]
fn reads_legacy_python_state_and_keeps_budget() {
    let value = json!({"paused":false,"history":[[1795352000.5,1795352100.5]],"lease":{"name":"old-python-lease","start":1795352000.5,"last":1795352050.0,"deadline":1795353800.5,"bearer":"old-token","download":"","id":"testpod123","rate":0.27,"ready":true}});
    let s: state::State = serde_json::from_value(value).unwrap();
    assert!(!s.paused);
    assert_eq!(s.history[0][1], 1795352100.5);
    assert!(s.lease.unwrap().ready);
}

#[tokio::test]
async fn old_model_lease_is_released_before_new_allocation() {
    let f = fixture().await;
    f.controller.resume().await.unwrap();
    f.controller.ensure().await.unwrap();
    let mut state = f.controller.read().unwrap();
    state.lease.as_mut().unwrap().model = None; // legacy Python lease
    f.controller.save(&state).unwrap();
    assert!(f.controller.ensure().await.is_err());
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 1);
    assert_eq!(f.fake.deletes.load(Ordering::SeqCst), 1);
    let state = f.controller.read().unwrap();
    assert!(state.lease.is_none());
    assert_eq!(state.history.len(), 1);
}
#[test]
fn forwards_json_tool_calls_and_bounds_thinking() {
    let model = Model::load().unwrap();
    let request = json!({"model":model.id,"messages":[
        {"role":"assistant","content":null,"tool_calls":[{"id":"call1","type":"function","function":{"name":"read","arguments":"{}"}}]},
        {"role":"tool","tool_call_id":"call1","content":"file contents"}],
        "tools":[{"type":"function","function":{"name":"read","parameters":{"type":"object"}}}],
        "tool_choice":"auto","max_completion_tokens":32768,"reasoning_budget":999999});
    let parsed = chat_body(request, &model.id).unwrap();
    assert!(parsed["tools"].is_array());
    assert_eq!(parsed["max_tokens"], 4096);
    assert_eq!(parsed["reasoning_budget"], 1024);
    assert_eq!(parsed["messages"][1]["role"], "tool");
    let instant=chat_body(json!({"model":model.id,"messages":[{"role":"user","content":"hello"}],"chat_template_kwargs":{"enable_thinking":false}}),&model.id).unwrap();
    assert!(instant.get("reasoning_budget").is_none());
    assert!(chat_body(json!({"model":model.id,"messages":[{"role":"user","content":[{"type":"image_url","image_url":{"url":"http://private"}}]}]}),&model.id).is_err());
}
#[tokio::test]
async fn launcher_free_http_preserves_protocol_discovery_pause_and_idle_cleanup() {
    let mut f = fixture().await;
    let file = f._tmp.path().join("weights.gguf");
    fs::write(&file, b"test").unwrap();
    f.controller.model.bytes = 4;
    let mut app = App::new(f.controller.clone()).unwrap();
    app.weight = file;
    app.upstream = Some(f.base.trim_end_matches('/').into());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!(
        "http://{}/v1/chat/completions",
        listener.local_addr().unwrap()
    );
    let routes = chat_router(app);
    let task = tokio::spawn(async move {
        axum::serve(listener, routes).await.unwrap();
    });
    let client = reqwest::Client::new();
    let body = json!({"model":f.controller.model.id,"stream":true,"messages":[{"role":"user","content":"hello"}]});
    let req = || {
        client
            .post(&url)
            .header(header::HOST, "127.0.0.1:18091")
            .header(HEADER, "1")
            .json(&body)
    };
    assert_eq!(req().send().await.unwrap().status(), StatusCode::FORBIDDEN);
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 0);
    f.controller.initialize_on_demand().await.unwrap();
    let before = fs::read(f._tmp.path().join("state.json")).unwrap();
    let models_url = url.replace("/chat/completions", "/models");
    let discovery: Value = client
        .get(&models_url)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(discovery["data"][0]["id"], f.controller.model.id);
    assert_eq!(fs::read(f._tmp.path().join("state.json")).unwrap(), before);
    // Selection/discovery and malformed or browser requests must never allocate.
    assert_eq!(
        req()
            .header(header::ORIGIN, "https://example.com")
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        client
            .post(&url)
            .header(header::HOST, "example.com")
            .header(HEADER, "1")
            .json(&body)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        client
            .post(&url)
            .header(header::HOST, "127.0.0.1:18091")
            .json(&body)
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        req()
            .json(&json!({"model":"other","messages":[{"role":"user","content":"hello"}]}))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::BAD_REQUEST
    );
    assert_eq!(
        req()
            .json(&json!({"model":f.controller.model.id,"messages":[]}))
            .send()
            .await
            .unwrap()
            .status(),
        StatusCode::BAD_REQUEST
    );
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 0);
    let response = req().send().await.unwrap();
    assert!(response.status().is_success());
    assert!(response.text().await.unwrap().contains("mock reply"));
    tokio::time::sleep(Duration::from_millis(20)).await;
    f.clock.fetch_add(121, Ordering::SeqCst);
    f.controller.reap(None).await.unwrap();
    assert!(f.controller.read().unwrap().lease.is_none());
    // A later prompt wakes a new Pod without any launcher or resume action.
    assert!(
        req()
            .send()
            .await
            .unwrap()
            .text()
            .await
            .unwrap()
            .contains("mock reply")
    );
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 2);
    f.controller.pause().await.unwrap();
    f.controller.initialize_on_demand().await.unwrap();
    assert_eq!(req().send().await.unwrap().status(), StatusCode::FORBIDDEN);
    assert_eq!(
        client.get(&models_url).send().await.unwrap().status(),
        StatusCode::OK
    );
    assert_eq!(f.fake.posts.load(Ordering::SeqCst), 2);
    task.abort();
}
#[test]
fn wrong_price_and_id_fail_validation() {
    assert!(!api::valid_rate(Some(0.69)));
    assert!(!api::valid_rate(Some(f64::NAN)));
    assert!(!api::valid_id("../other-pod"));
    assert!(api::valid_id("known123"));
}
