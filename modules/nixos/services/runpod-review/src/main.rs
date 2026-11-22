mod api;
mod state;
#[cfg(test)]
mod tests;

use axum::{
    Json, Router,
    body::Body,
    extract::{DefaultBodyLimit, State as ExtractState},
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use futures_util::StreamExt;
use serde::Deserialize;
use serde_json::{Value, json};
use state::{Controller, Lease, Lock};
use std::{fmt, fs, os::unix::fs::PermissionsExt, path::PathBuf, sync::Arc, time::Duration};
use subtle::ConstantTimeEq;
use tokio::sync::{Mutex, OwnedMutexGuard};

const DIRECTORY: &str = "/var/lib/runpod-review";
const SOCKET: &str = "/run/runpod-review/chat.sock";
const HEADER: &str = "X-Shimmers-GPU-Review";

#[derive(Clone, Deserialize)]
pub struct Model {
    id: String,
    file: String,
    bytes: u64,
    sha256: String,
}
impl Model {
    fn load() -> Result<Self, Error> {
        serde_json::from_str(include_str!("../model.json")).map_err(|_| Error::internal())
    }
    fn path(&self) -> PathBuf {
        PathBuf::from("/var/lib/llm/models").join(&self.file)
    }
}

#[derive(Debug)]
pub struct Error {
    message: &'static str,
    status: StatusCode,
}
impl Error {
    fn unavailable(message: &'static str) -> Self {
        Self {
            message,
            status: StatusCode::BAD_REQUEST,
        }
    }
    fn paused() -> Self {
        Self {
            message: "GPU is explicitly paused; run gpu-review-resume, then send your prompt in OpenCode",
            status: StatusCode::FORBIDDEN,
        }
    }
    fn internal() -> Self {
        Self {
            message: "Gateway state or configuration error; no automatic allocation retry",
            status: StatusCode::BAD_REQUEST,
        }
    }
}
impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.message)
    }
}
impl std::error::Error for Error {}
impl IntoResponse for Error {
    fn into_response(self) -> Response {
        (
            self.status,
            Json(json!({"error":{"message":self.message,"type":"runpod_gateway"}})),
        )
            .into_response()
    }
}

fn chat_body(mut body: Value, model: &str) -> Result<Value, Error> {
    let bad = || Error::unavailable("Invalid text/tool conversation or model identifier");
    let object = body.as_object_mut().ok_or_else(bad)?;
    if object.get("model").and_then(Value::as_str) != Some(model) {
        return Err(bad());
    }
    let messages = object
        .get("messages")
        .and_then(Value::as_array)
        .ok_or_else(bad)?;
    if messages.is_empty() || messages.len() > 2048 {
        return Err(bad());
    }
    for m in messages {
        if !matches!(
            m["role"].as_str(),
            Some("system" | "user" | "assistant" | "tool")
        ) {
            return Err(bad());
        }
        match &m["content"] {
            Value::String(_) => (),
            Value::Null if m["role"] == "assistant" && m["tool_calls"].is_array() => (),
            Value::Array(parts)
                if parts
                    .iter()
                    .all(|p| p["type"] == "text" && p["text"].is_string()) => {}
            _ => return Err(bad()),
        }
        if m["role"] == "tool" && !m["tool_call_id"].is_string() {
            return Err(bad());
        }
    }
    let tokens = object
        .get("max_tokens")
        .or_else(|| object.get("max_completion_tokens"))
        .map(|v| v.as_u64().filter(|n| *n > 0).ok_or_else(bad))
        .transpose()?
        .unwrap_or(4096)
        .min(4096);
    if object.get("stream").is_some_and(|v| !v.is_boolean()) {
        return Err(bad());
    }
    let thinking = object
        .get("chat_template_kwargs")
        .and_then(|v| v.get("enable_thinking"))
        .map(|v| v.as_bool().ok_or_else(bad))
        .transpose()?
        .unwrap_or(true);
    // Forward only the OpenAI protocol fields needed by the agent. No arbitrary
    // file URLs, provider options, model override or HTTP headers can slip through.
    const ALLOWED: &[&str] = &[
        "model",
        "messages",
        "tools",
        "tool_choice",
        "parallel_tool_calls",
        "stream",
        "stream_options",
    ];
    object.retain(|key, _| ALLOWED.contains(&key.as_str()));
    object.insert("max_tokens".into(), json!(tokens));
    object.insert(
        "chat_template_kwargs".into(),
        json!({"enable_thinking":thinking}),
    );
    if thinking {
        object.insert("reasoning_budget".into(), json!(1024));
    }
    object.insert("temperature".into(), json!(0.6));
    object.insert("top_p".into(), json!(0.95));
    object.insert("top_k".into(), json!(20));
    object.insert("min_p".into(), json!(0));
    Ok(body)
}

#[derive(Clone)]
struct App {
    controller: Controller,
    http: reqwest::Client,
    slot: Arc<Mutex<()>>,
    weight: PathBuf,
    #[cfg(test)]
    upstream: Option<String>,
}
impl App {
    fn new(controller: Controller) -> Result<Self, Error> {
        Ok(Self {
            weight: controller.model.path(),
            controller,
            http: reqwest::Client::builder()
                .no_proxy()
                .connect_timeout(Duration::from_secs(10))
                .read_timeout(Duration::from_secs(120))
                .build()
                .map_err(|_| Error::internal())?,
            slot: Arc::new(Mutex::new(())),
            #[cfg(test)]
            upstream: None,
        })
    }
    fn upstream(&self, lease: &Lease) -> String {
        #[cfg(test)]
        if let Some(url) = &self.upstream {
            return url.clone();
        }
        format!(
            "https://{}-8080.proxy.runpod.net",
            lease.id.as_ref().unwrap()
        )
    }
    async fn ready(&self, lease: &Lease, url: &str) -> Result<(), Error> {
        while (self.controller.clock)() < lease.deadline {
            let current = self.controller.read()?;
            if !current
                .lease
                .as_ref()
                .is_some_and(|l| l.name == lease.name && !l.closing)
            {
                return Err(Error::unavailable("Pod lease ended during startup"));
            }
            if let Ok(response) = self
                .http
                .get(format!("{url}/v1/models"))
                .bearer_auth(&lease.bearer)
                .timeout(Duration::from_secs(5))
                .send()
                .await
                && response.status().is_success()
                && let Ok(data) = response.json::<Value>().await
                && data["data"]
                    .as_array()
                    .is_some_and(|rows| rows.iter().any(|m| m["id"] == self.controller.model.id))
            {
                return Ok(());
            }
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
        Err(Error::unavailable("GPU startup deadline reached"))
    }
}

// Retain both locks until the stream ends OR the client disconnects. Update the
// idle timestamp before releasing them, including on cancellation. Queued
// clients already hold shared locks so the independent reaper won't kill them.
struct SessionGuard {
    controller: Controller,
    name: Option<String>,
    active: Option<Lock>,
    slot: Option<OwnedMutexGuard<()>>,
}
impl Drop for SessionGuard {
    fn drop(&mut self) {
        if let Some(name) = self.name.take() {
            let controller = self.controller.clone();
            let active = self.active.take();
            let slot = self.slot.take();
            tokio::spawn(async move {
                let _ = controller.touch(&name, false).await;
                drop((active, slot));
            });
        }
    }
}

async fn models(ExtractState(app): ExtractState<App>) -> Json<Value> {
    Json(
        json!({"object":"list", "data":[{"id":app.controller.model.id,"object":"model","owned_by":"shimmers"}]}),
    )
}
async fn weights(
    ExtractState(app): ExtractState<App>,
    headers: HeaderMap,
) -> Result<Response, StatusCode> {
    let state = app.controller.read().map_err(|_| StatusCode::NOT_FOUND)?;
    let lease = state
        .lease
        .filter(|l| !l.download.is_empty() && !l.closing && l.deadline > (app.controller.clock)())
        .ok_or(StatusCode::NOT_FOUND)?;
    let expected = format!("Bearer {}", lease.download);
    let actual = headers
        .get(header::AUTHORIZATION)
        .map_or(&[][..], |h| h.as_bytes());
    if actual.ct_eq(expected.as_bytes()).unwrap_u8() != 1 {
        return Err(StatusCode::NOT_FOUND);
    }
    Ok((
        [("X-Accel-Redirect", "/_private/model.gguf")],
        Body::empty(),
    )
        .into_response())
}
async fn chat(
    ExtractState(app): ExtractState<App>,
    headers: HeaderMap,
    Json(body): Json<Value>,
) -> Result<Response, Error> {
    if headers.contains_key(header::ORIGIN)
        || headers.get(header::HOST).and_then(|h| h.to_str().ok()) != Some("127.0.0.1:18091")
        || headers.get(HEADER).and_then(|h| h.to_str().ok()) != Some("1")
    {
        return Err(Error {
            message: "GPU requests require the trusted local OpenCode endpoint",
            status: StatusCode::FORBIDDEN,
        }); // never allow a website to cause paid allocations through localhost
    }
    let body = chat_body(body, &app.controller.model.id)?;
    if fs::metadata(&app.weight).map_or(true, |m| {
        !m.is_file() || m.len() != app.controller.model.bytes
    }) {
        return Err(Error::unavailable(
            "Run gpu-review-prepare to verify the Qwen3.6 weights on shimmers",
        ));
    }
    let mut guard = SessionGuard {
        controller: app.controller.clone(),
        name: None,
        active: Some(app.controller.active()?),
        slot: None,
    };
    guard.slot = Some(app.slot.clone().lock_owned().await);
    let lease = app.controller.ensure().await?;
    guard.name = Some(lease.name.clone());
    let url = app.upstream(&lease);
    if !lease.ready {
        if let Err(error) = app.ready(&lease, &url).await {
            let _ = app.controller.reap(Some(&lease.name)).await;
            return Err(error);
        }
        app.controller.touch(&lease.name, true).await?;
    }
    let response = app
        .http
        .post(format!("{url}/v1/chat/completions"))
        .bearer_auth(&lease.bearer)
        .json(&body)
        .send()
        .await
        .map_err(|_| {
            Error::unavailable(
                "GPU inference unavailable; retry manually after checking gpu-review-status",
            )
        })?;
    if !response.status().is_success() {
        return Err(Error::unavailable(
            "GPU inference rejected the request; check context size and Pod status",
        ));
    }
    let content_type = response
        .headers()
        .get(header::CONTENT_TYPE)
        .cloned()
        .unwrap_or_else(|| "application/json".parse().unwrap());
    let mut bytes = response.bytes_stream();
    let stream = async_stream::stream! {
        let _guard = guard;
        while let Some(chunk) = bytes.next().await {
            match chunk {
                Ok(bytes) => yield Ok::<_, std::io::Error>(bytes),
                Err(_) => { yield Err(std::io::Error::other("GPU stream interrupted")); break; }
            }
        }
    };
    let mut response = Body::from_stream(stream).into_response();
    response
        .headers_mut()
        .insert(header::CONTENT_TYPE, content_type);
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, "no-store".parse().unwrap());
    Ok(response)
}

fn chat_router(app: App) -> Router {
    Router::new()
        .route("/v1/models", get(models))
        .route("/v1/chat/completions", post(chat))
        .layer(DefaultBodyLimit::max(2 * 1024 * 1024))
        .with_state(app)
}
fn weight_router(app: App) -> Router {
    Router::new()
        .route("/model.gguf", get(weights))
        .with_state(app)
}

async fn shutdown() {
    let mut terminate =
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).unwrap();
    tokio::select! { _ = tokio::signal::ctrl_c() => (), _ = terminate.recv() => () }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let action = std::env::args().nth(1).unwrap_or_else(|| "serve".into());
    let key = if action == "status" {
        None
    } else {
        let credentials = std::env::var("CREDENTIALS_DIRECTORY")?;
        let key = fs::read_to_string(PathBuf::from(credentials).join("runpod-key"))?;
        if key.trim().is_empty() {
            return Err("Missing Runpod credential".into());
        }
        Some(ApiKey(key.trim().to_owned()))
    };
    let controller = Controller::new(
        DIRECTORY.into(),
        key.map(|k| api::Api::new(k.0)).transpose()?,
    )?;
    match action.as_str() {
        "status" => println!("{}", serde_json::to_string_pretty(&controller.status()?)?),
        "pause" => controller.pause().await?,
        "resume" => controller.resume().await?,
        "reap" => controller.reap(None).await?,
        "release" => {
            let state = controller.read()?;
            controller
                .reap(state.lease.as_ref().map(|l| l.name.as_str()))
                .await?;
        }
        "serve" => {
            controller.initialize_on_demand().await?;
            let app = App::new(controller)?;
            match fs::remove_file(SOCKET) {
                Ok(()) => (),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
                Err(e) => return Err(e.into()),
            }
            let listener = tokio::net::UnixListener::bind(SOCKET)?;
            fs::set_permissions(SOCKET, fs::Permissions::from_mode(0o660))?;
            let weights = tokio::net::TcpListener::bind("127.0.0.1:18092").await?;
            tokio::try_join!(
                axum::serve(listener, chat_router(app.clone())).with_graceful_shutdown(shutdown()),
                axum::serve(weights, weight_router(app)).with_graceful_shutdown(shutdown())
            )?;
        }
        _ => return Err("Expected serve, status, pause, resume, reap or release".into()),
    }
    Ok(())
}
struct ApiKey(String);
