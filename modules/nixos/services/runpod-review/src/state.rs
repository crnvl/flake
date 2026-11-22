use crate::{
    Error, Model,
    api::{self, Api},
};
use chrono::{Datelike, TimeZone, Utc};
use fs2::FileExt;
use rand::{RngCore, rngs::OsRng};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    path::PathBuf,
    sync::Arc,
    time::{SystemTime, UNIX_EPOCH},
};

pub const IDLE: f64 = 120.0;
pub const LIFETIME: f64 = 1800.0;
const MONTHLY: f64 = 6.0 * 3600.0;

pub fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs_f64()
}
fn token() -> String {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

// Compatible with the Python controller's persisted JSON. Do not discard budget
// history or an uncertain/in-flight allocation during the language migration.
#[derive(Clone, Serialize, Deserialize)]
pub struct Lease {
    pub name: String,
    pub start: f64,
    pub last: f64,
    pub deadline: f64,
    pub bearer: String,
    #[serde(default)]
    pub download: String,
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub rate: Option<f64>,
    #[serde(default)]
    pub ready: bool,
    #[serde(default)]
    pub closing: bool,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default = "default_gpu")]
    pub gpu: String,
}

fn default_gpu() -> String {
    api::GPU.into()
}

#[derive(Serialize, Deserialize)]
pub struct State {
    pub lease: Option<Lease>,
    #[serde(default)]
    pub history: Vec<[f64; 2]>,
    #[serde(default = "yes")]
    pub paused: bool,
    #[serde(default)]
    pub on_demand_initialized: bool,
}
fn yes() -> bool {
    true
}
impl Default for State {
    fn default() -> Self {
        Self {
            lease: None,
            history: vec![],
            paused: true,
            on_demand_initialized: false,
        }
    }
}

pub struct Lock(File);
impl Drop for Lock {
    fn drop(&mut self) {
        let _ = FileExt::unlock(&self.0);
    }
}

#[derive(Clone)]
pub struct Controller {
    pub dir: PathBuf,
    pub model: Model,
    pub api: Option<Api>,
    pub clock: Arc<dyn Fn() -> f64 + Send + Sync>,
}

impl Controller {
    pub fn new(dir: PathBuf, api: Option<Api>) -> Result<Self, Error> {
        Ok(Self {
            dir,
            api,
            model: Model::load()?,
            clock: Arc::new(now),
        })
    }
    pub fn read(&self) -> Result<State, Error> {
        match fs::read(self.dir.join("state.json")) {
            Ok(bytes) => serde_json::from_slice(&bytes)
                .map_err(|_| Error::unavailable("Unreadable lease state; no allocation permitted")),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(State::default()),
            Err(_) => Err(Error::internal()),
        }
    }
    pub fn save(&self, state: &State) -> Result<(), Error> {
        let mut file = File::create(self.dir.join("state.tmp")).map_err(|_| Error::internal())?;
        file.write_all(&serde_json::to_vec(state).map_err(|_| Error::internal())?)
            .map_err(|_| Error::internal())?;
        file.sync_all().map_err(|_| Error::internal())?;
        fs::rename(self.dir.join("state.tmp"), self.dir.join("state.json"))
            .map_err(|_| Error::internal())?;
        File::open(&self.dir)
            .and_then(|d| d.sync_all())
            .map_err(|_| Error::internal())
    }
    fn file(&self, name: &str) -> Result<File, Error> {
        OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(self.dir.join(name))
            .map_err(|_| Error::internal())
    }
    pub async fn gate(&self) -> Result<Lock, Error> {
        let file = self.file("gate")?;
        tokio::task::spawn_blocking(move || {
            FileExt::lock_exclusive(&file).map_err(|_| Error::internal())?;
            Ok(Lock(file))
        })
        .await
        .map_err(|_| Error::internal())?
    }
    pub fn active(&self) -> Result<Lock, Error> {
        let file = self.file("requests")?;
        FileExt::try_lock_shared(&file)
            .map_err(|_| Error::unavailable("GPU cleanup in progress"))?;
        Ok(Lock(file))
    }
    fn idle_lock(&self) -> Result<Option<Lock>, Error> {
        let file = self.file("requests")?;
        match FileExt::try_lock_exclusive(&file) {
            Ok(()) => Ok(Some(Lock(file))),
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => Ok(None),
            Err(_) => Err(Error::internal()),
        }
    }
    fn api(&self) -> Result<&Api, Error> {
        self.api.as_ref().ok_or_else(Error::internal)
    }

    // One-time opt-in when deploying launcher-free OpenCode integration. Keep
    // existing leases/tokens/budget intact; never unpause again on a restart.
    pub async fn initialize_on_demand(&self) -> Result<(), Error> {
        let _gate = self.gate().await?;
        let mut state = self.read()?;
        if !state.on_demand_initialized {
            state.paused = false;
            state.on_demand_initialized = true;
            self.save(&state)?;
        }
        Ok(())
    }

    pub async fn ensure(&self) -> Result<Lease, Error> {
        let _gate = self.gate().await?;
        let mut state = self.read()?;
        if state.paused {
            return Err(Error::paused());
        }
        if let Some(lease) = &state.lease {
            if lease.id.is_none() {
                return Err(Error::unavailable(
                    "Previous allocation is unconfirmed; cleanup must reconcile it before another Pod can start",
                ));
            }
            if lease.closing || (self.clock)() >= lease.deadline {
                // Close under the allocation gate. Only confirmed deletion can
                // clear this lease; failures/cancellation block any replacement.
                self.close(&mut state).await?;
            } else {
                if lease.model.as_deref() != Some(self.model.id.as_str()) {
                    self.close(&mut state).await?;
                    return Err(Error::unavailable(
                        "Previous-model Pod released; send a new request to use Qwen3.6",
                    ));
                }
                return Ok(lease.clone());
            }
        }
        let now = (self.clock)(); // include cleanup time in history before budgeting a new lease
        let date = Utc
            .timestamp_opt(now as i64, 0)
            .single()
            .ok_or_else(Error::internal)?;
        let month = Utc
            .with_ymd_and_hms(date.year(), date.month(), 1, 0, 0, 0)
            .single()
            .ok_or_else(Error::internal)?
            .timestamp() as f64;
        state.history.retain(|[_, end]| *end > month);
        let left = MONTHLY
            - state
                .history
                .iter()
                .map(|[start, end]| end - start.max(month))
                .sum::<f64>();
        if left < IDLE {
            return Err(Error::unavailable(
                "GPU trial allowance exhausted for this UTC month",
            ));
        }
        let api = self.api()?;
        let offer = api.check_price().await?;
        let lease = Lease {
            name: format!("shimmers-review-{}", &token()[..24]),
            start: now,
            last: now,
            deadline: now + left.min(LIFETIME),
            bearer: token(),
            download: token(),
            id: None,
            rate: None,
            ready: false,
            closing: false,
            model: Some(self.model.id.clone()),
            gpu: offer.gpu,
        };
        state.lease = Some(lease.clone());
        self.save(&state)?; // durable BEFORE POST; an ambiguous response must not cause a second allocation
        let response = api
            .request(
                reqwest::Method::POST,
                "pods",
                Some(Api::create_body(&lease, &self.model)),
            )
            .await?;
        let status = response.status();
        if !status.is_success() {
            if matches!(
                status.as_u16(),
                400 | 401 | 402 | 403 | 404 | 413 | 422 | 429
            ) {
                state.lease = None;
                self.save(&state)?;
            }
            return Err(Error::unavailable(
                "Runpod rejected or could not confirm allocation",
            ));
        }
        let pod = Api::json(response).await?;
        let mut lease = lease;
        lease.id = pod["id"].as_str().map(str::to_owned);
        lease.rate = pod["cost"].as_f64();
        state.lease = Some(lease.clone());
        self.save(&state)?;
        if !lease.id.as_deref().is_some_and(api::valid_id)
            || pod["cloud"] != "SECURE"
            || pod["gpu"]["id"] != lease.gpu
            || pod["gpu"]["count"] != 1
            || !api::valid_rate(lease.rate)
        {
            self.close(&mut state).await?;
            return Err(Error::unavailable(
                "Allocated GPU or price did not match the trial constraints",
            ));
        }
        Ok(lease)
    }

    pub async fn close(&self, state: &mut State) -> Result<(), Error> {
        let Some(lease) = state.lease.as_mut() else {
            return Ok(());
        };
        lease.closing = true;
        lease.download.clear();
        self.save(state)?;
        let lease = state.lease.as_ref().unwrap();
        let id = match &lease.id {
            Some(id) => id.clone(),
            None => self.api()?.find(&lease.name).await?.ok_or_else(|| {
                Error::unavailable("Allocation outcome unknown; verify named Pod in Runpod console")
            })?,
        };
        self.api()?.delete(&id).await?;
        state.history.push([lease.start, (self.clock)()]);
        state.lease = None;
        self.save(state)
    }
    pub async fn touch(&self, name: &str, ready: bool) -> Result<(), Error> {
        let _gate = self.gate().await?;
        let mut state = self.read()?;
        if let Some(l) = state
            .lease
            .as_mut()
            .filter(|l| l.name == name && !l.closing)
        {
            l.last = (self.clock)();
            if ready {
                l.ready = true;
                l.download.clear();
            }
            self.save(&state)?;
        }
        Ok(())
    }
    pub async fn reap(&self, failed_name: Option<&str>) -> Result<(), Error> {
        let _gate = self.gate().await?;
        let mut state = self.read()?;
        if let Some(l) = &state.lease {
            let now = (self.clock)();
            if l.closing
                || now >= l.deadline
                || Some(l.name.as_str()) == failed_name
                || l.model.as_deref() != Some(self.model.id.as_str())
            {
                self.close(&mut state).await?;
            } else if now >= l.last + IDLE
                && let Some(_requests) = self.idle_lock()?
            {
                self.close(&mut state).await?;
            }
        }
        Ok(())
    }
    pub async fn pause(&self) -> Result<(), Error> {
        let _gate = self.gate().await?;
        let mut state = self.read()?;
        state.paused = true;
        state.on_demand_initialized = true; // an explicit pause always beats first-time setup
        self.save(&state)?;
        self.close(&mut state).await
    }
    pub async fn resume(&self) -> Result<(), Error> {
        let _gate = self.gate().await?;
        let mut state = self.read()?;
        if state
            .lease
            .as_ref()
            .is_some_and(|l| l.closing || (self.clock)() >= l.deadline)
        {
            return Err(Error::unavailable(
                "Previous Pod needs cleanup before resuming",
            ));
        }
        state.paused = false;
        state.on_demand_initialized = true;
        self.save(&state)
    }
    pub fn status(&self) -> Result<Value, Error> {
        let state = self.read()?;
        let l = state.lease.as_ref();
        Ok(
            json!({"paused":state.paused, "on_demand_initialized":state.on_demand_initialized, "gpu":l.map_or(api::GPU, |l| l.gpu.as_str()), "gpu_preference":api::GPU_PREFERENCE, "model":self.model.id,
                "pod":l.and_then(|l| l.id.as_ref()), "ready":l.is_some_and(|l| l.ready),
                "closing":l.is_some_and(|l| l.closing), "idle_timeout_seconds":IDLE,
                "maximum_lease_seconds":LIFETIME, "hourly_price_ceiling_usd":api::MAX_RATE,
                "remaining_seconds":l.map_or(0.0,|l| (l.deadline-(self.clock)()).max(0.0).round()),
                "estimated_compute_usd":l.map_or(0.0,|l| (((self.clock)()-l.start).max(0.0)*l.rate.unwrap_or(api::MAX_RATE)/3600.0*10000.0).round()/10000.0)
            }),
        )
    }
}
