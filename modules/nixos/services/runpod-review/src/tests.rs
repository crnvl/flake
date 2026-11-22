use super::*;
use axum::routing::delete;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

#[derive(Clone)]
struct Fake {
    posts: Arc<AtomicUsize>,
    deletes: Arc<AtomicUsize>,
    lost_reply: Arc<AtomicBool>,
    delete_failure: Arc<AtomicBool>,
    creation: Arc<Mutex<Value>>,
    completion: Arc<Mutex<Value>>,
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
        creation: Arc::new(Mutex::new(Value::Null)),
        completion: Arc::new(Mutex::new(Value::Null)),
    };
    let router = Router::new()
        .route("/catalog/gpus", get(|axum::extract::Query(query):axum::extract::Query<std::collections::HashMap<String,String>>| async move {
            assert_eq!(query.get("include").unwrap(),"AVAILABILITY");assert_eq!(query.get("cloud").unwrap(),"SECURE");
            Json(json!({"gpus":[{"id":api::GPU,"secure":true,"availability":"LOW","price":{"secure":0.27}}]}))
        }))
        .route("/pods", post(|ExtractState(fake):ExtractState<Fake>,Json(body):Json<Value>| async move {
            fake.posts.fetch_add(1,Ordering::SeqCst);*fake.creation.lock().await=body;
            if fake.lost_reply.load(Ordering::SeqCst) { StatusCode::BAD_GATEWAY.into_response() }
            else { Json(json!({"id":"testpod123","cost":0.27,"cloud":"SECURE","gpu":{"id":api::GPU,"count":1}})).into_response() }
        }).get(|ExtractState(fake):ExtractState<Fake>| async move {
            let body=fake.creation.lock().await;Json(json!({"pods":[{"id":"testpod123","name":body["name"]}],"pagination":{"hasNextPage":false}}))
        }))
        .route("/pods/testpod123",delete(|ExtractState(fake):ExtractState<Fake>|async move {
            fake.deletes.fetch_add(1,Ordering::SeqCst);
            if fake.delete_failure.load(Ordering::SeqCst) { StatusCode::BAD_GATEWAY } else { StatusCode::NO_CONTENT }
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
    assert!(f.controller.read().unwrap().paused);
    assert!(f.controller.resume().await.is_err());
    f.fake.delete_failure.store(false, Ordering::SeqCst);
    f.controller.reap(None).await.unwrap();
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
async fn http_stream_keeps_protocol_and_releases_locks() {
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
    f.controller.resume().await.unwrap();
    let response = req().send().await.unwrap();
    assert!(response.status().is_success());
    assert!(response.text().await.unwrap().contains("mock reply"));
    tokio::time::sleep(Duration::from_millis(20)).await;
    f.clock.fetch_add(121, Ordering::SeqCst);
    f.controller.reap(None).await.unwrap();
    assert!(f.controller.read().unwrap().lease.is_none());
    task.abort();
}
#[test]
fn wrong_price_and_id_fail_validation() {
    assert!(!api::valid_rate(Some(0.59)));
    assert!(!api::valid_rate(Some(f64::NAN)));
    assert!(!api::valid_id("../other-pod"));
    assert!(api::valid_id("known123"));
}
