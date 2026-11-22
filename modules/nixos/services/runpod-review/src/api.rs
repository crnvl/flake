use crate::{Error, Model, state::Lease};
use reqwest::{Client, StatusCode};
use serde_json::{Value, json};
use std::time::Duration;

pub const GPU: &str = "NVIDIA RTX A5000";
pub const MAX_RATE: f64 = 0.30;
const IMAGE: &str = "ghcr.io/ggml-org/llama.cpp@sha256:ac11e113c61a57b0b0b86414aa8e1b61b9512dcedf8083c5fdedb35b379342cf";

#[derive(Clone)]
pub struct Api {
    pub client: Client,
    pub base: String,
    key: String,
}

impl Api {
    pub fn new(key: String) -> Result<Self, Error> {
        Ok(Self {
            client: Client::builder()
                .no_proxy()
                .timeout(Duration::from_secs(20))
                .build()
                .map_err(|_| Error::internal())?,
            base: "https://api.runpod.io/v2/".into(),
            key,
        })
    }

    pub async fn request(
        &self,
        method: reqwest::Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<reqwest::Response, Error> {
        let mut request = self
            .client
            .request(method, format!("{}{path}", self.base))
            .bearer_auth(&self.key);
        if let Some(body) = body {
            request = request.json(&body);
        }
        request.send().await.map_err(|_| {
            Error::unavailable(
                "Runpod API unreachable; allocation will not be retried automatically",
            )
        })
    }

    pub async fn json(response: reqwest::Response) -> Result<Value, Error> {
        if !response.status().is_success() {
            return Err(Error::unavailable("Runpod API rejected the request"));
        }
        // Never return API response bodies or debug representations of credentials.
        response
            .json()
            .await
            .map_err(|_| Error::unavailable("Invalid Runpod response"))
    }

    pub async fn check_price(&self) -> Result<(), Error> {
        let data = Self::json(
            self.request(
                reqwest::Method::GET,
                "catalog/gpus?product=POD&include=AVAILABILITY&cloud=SECURE&minCudaVersion=12.8",
                None,
            )
            .await?,
        )
        .await?;
        let found = data["gpus"]
            .as_array()
            .ok_or_else(Error::internal)?
            .iter()
            .any(|g| {
                g["id"] == GPU
                    && g["secure"] == true
                    && matches!(g["availability"].as_str(), Some("LOW" | "MEDIUM" | "HIGH"))
                    && valid_rate(g["price"]["secure"].as_f64())
            });
        if found {
            Ok(())
        } else {
            Err(Error::unavailable(
                "A5000 unavailable within the $0.30/hour ceiling",
            ))
        }
    }

    pub fn create_body(lease: &Lease, model: &Model) -> Value {
        let script = format!(
            r#"set -eu
umask 077
curl --fail --silent --show-error --proto '=https' --max-time 1620 \
  -H "Authorization: Bearer $WEIGHTS_TOKEN" -o /tmp/model.gguf https://review-weights.shimme.rs/model.gguf
echo '{}  /tmp/model.gguf' | sha256sum -c -
unset WEIGHTS_TOKEN
exec /app/llama-server --model /tmp/model.gguf --alias {} --host 0.0.0.0 --port 8080 \
  --parallel 1 --ctx-size 65536 --n-gpu-layers 99 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 \
  --cache-ram 512 --ctx-checkpoints 4 --jinja --reasoning-format deepseek --no-ui --no-slots --log-disable
"#,
            model.sha256, model.id
        );
        json!({
            "name": lease.name, "cloud": "SECURE", "gpu": {"id": GPU, "count": 1, "minCudaVersion": "12.8"},
            "image": IMAGE, "disk": 40, "mounts": {}, "ports": ["8080/http"],
            "entrypoint": ["/usr/bin/timeout", "--signal=TERM", "1770", "/bin/sh", "-c"], "cmd": [script],
            "env": {"WEIGHTS_TOKEN": lease.download, "LLAMA_API_KEY": lease.bearer}
        })
    }

    pub async fn find(&self, name: &str) -> Result<Option<String>, Error> {
        let mut url = format!("{}pods", self.base);
        loop {
            let response = self
                .client
                .get(&url)
                .bearer_auth(&self.key)
                .send()
                .await
                .map_err(|_| Error::unavailable("Cannot reconcile Runpod lease"))?;
            let data = Self::json(response).await?;
            for pod in data["pods"].as_array().ok_or_else(Error::internal)? {
                if pod["name"] == name {
                    return Ok(pod["id"].as_str().map(str::to_owned));
                }
            }
            if data["pagination"]["hasNextPage"] != true {
                return Ok(None);
            }
            let cursor = data["pagination"]["nextCursor"]
                .as_str()
                .ok_or_else(Error::internal)?;
            let mut next = reqwest::Url::parse(&format!("{}pods", self.base))
                .map_err(|_| Error::internal())?;
            next.query_pairs_mut().append_pair("cursor", cursor);
            url = next.into();
        }
    }

    pub async fn delete(&self, id: &str) -> Result<(), Error> {
        if !valid_id(id) {
            return Err(Error::unavailable("Unexpected Pod identifier"));
        }
        let response = self
            .request(reqwest::Method::DELETE, &format!("pods/{id}"), None)
            .await?;
        if response.status().is_success() || response.status() == StatusCode::NOT_FOUND {
            Ok(())
        } else {
            Err(Error::unavailable(
                "Pod deletion unconfirmed; cleanup timer will retry",
            ))
        }
    }
}

pub fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.bytes().all(|b| b.is_ascii_alphanumeric())
}
pub fn valid_rate(rate: Option<f64>) -> bool {
    rate.is_some_and(|r| r.is_finite() && r > 0.0 && r <= MAX_RATE)
}
