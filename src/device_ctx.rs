use idevice::{
    afc::AfcClient, diagnostics_relay::DiagnosticsRelayClient, lockdown::LockdownClient,
};
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use tracing::field::debug;

use crate::{image_cache, media_streamer::MediaStreamSession};

#[derive(Clone)]
#[allow(non_camel_case_types)]
pub struct iOSVersion {
    pub major: u32,
    pub minor: u32,
    pub patch: u32,
    pub raw_version_str: String,
}

impl iOSVersion {
    pub fn new(major: u32, minor: u32, patch: u32, raw_version_str: String) -> Self {
        Self {
            major,
            minor,
            patch,
            raw_version_str,
        }
    }

    pub fn from_str_opt(version_str: &str) -> Option<Self> {
        let parts: Vec<&str> = version_str.split('.').collect();
        if parts.len() != 3 {
            return None;
        }

        let major = parts[0].parse::<u32>().ok()?;
        let minor = parts[1].parse::<u32>().ok()?;
        let patch = parts[2].parse::<u32>().ok()?;

        Some(Self::new(major, minor, patch, version_str.to_string()))
    }

    pub fn from_str(version_str: &str) -> Self {
        let parts: Vec<&str> = version_str.split('.').collect();

        let major = parts
            .get(0)
            .and_then(|s| s.parse::<u32>().ok())
            .unwrap_or(0);
        let minor = parts
            .get(1)
            .and_then(|s| s.parse::<u32>().ok())
            .unwrap_or(0);
        let patch = parts
            .get(2)
            .and_then(|s| s.parse::<u32>().ok())
            .unwrap_or(0);

        Self::new(major, minor, patch, version_str.to_string())
    }
}

#[derive(Clone)]
pub struct DeviceServices {
    pub afc: Arc<Mutex<AfcClient>>,
    pub afc2: Option<Arc<Mutex<AfcClient>>>,
    pub diag: Arc<Mutex<DiagnosticsRelayClient>>,
    pub heartbeat_task: Option<Arc<JoinHandle<()>>>,
    pub video_streams: Arc<Mutex<HashMap<String, MediaStreamSession>>>,
    pub provider: Arc<Mutex<Box<dyn idevice::provider::IdeviceProvider>>>,
    pub lockdown: Arc<Mutex<LockdownClient>>,
    pub ios_version: iOSVersion,
}

static APP_DEVICE_STATE: Lazy<Mutex<HashMap<String, DeviceServices>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

pub async fn get_device(udid: impl Into<String>) -> anyhow::Result<DeviceServices> {
    let udid_str = udid.into();
    let maybe_device = APP_DEVICE_STATE.lock().await.get(&udid_str).cloned();

    match maybe_device {
        Some(d) => Ok(d),
        None => anyhow::bail!(format!("Device with udid {} does not exist", udid_str)),
    }
}

pub async fn get_device_opt(udid: impl Into<String>) -> Option<DeviceServices> {
    let udid_str = udid.into();
    APP_DEVICE_STATE.lock().await.get(&udid_str).cloned()
}

pub async fn clean_device_from_app_state(udid: &str) {
    let svc = APP_DEVICE_STATE.lock().await.remove(udid);
    if let Some(svc) = svc {
        if let Some(t) = &svc.heartbeat_task {
            t.abort();
        }

        let sessions = {
            let mut streams = svc.video_streams.lock().await;
            streams
                .drain()
                .map(|(_, session)| session)
                .collect::<Vec<_>>()
        };
        for mut session in sessions {
            session.shutdown().await;
        }

        image_cache::clear_for_udid(udid);

        println!("Removed device with UDID {}", udid);
    } else {
        eprintln!("Attempted to remove non-existent device with UDID {}", udid);
    }
}

/// Inserts a device into the global state and returns whether an existing connection
/// for the same UDID was replaced.
pub async fn insert_device(udid: impl Into<String>, services: DeviceServices) -> bool {
    let udid = udid.into();
    let mut state = APP_DEVICE_STATE.lock().await;
    if let Some(mut old) = state.insert(udid.clone(), services) {
        if let Some(task) = old.heartbeat_task.take() {
            task.abort();
        }
        eprintln!("Replaced existing device connection - UDID {}", udid);
        return true;
    }
    false
}

pub async fn insert_heartbeat_task(udid: impl Into<String>, task: Arc<JoinHandle<()>>) {
    let mut state = APP_DEVICE_STATE.lock().await;
    if let Some(svc) = state.get_mut(&udid.into()) {
        svc.heartbeat_task = Some(task);
    }
}
