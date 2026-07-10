use idevice::{
    afc::AfcClient, diagnostics_relay::DiagnosticsRelayClient, lockdown::LockdownClient,
};
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;

use crate::image_cache;

#[derive(Clone)]
pub struct DeviceServices {
    pub afc: Arc<Mutex<AfcClient>>,
    pub afc2: Option<Arc<Mutex<AfcClient>>>,
    pub diag: Arc<Mutex<DiagnosticsRelayClient>>,
    pub heartbeat_task: Option<Arc<JoinHandle<()>>>,
    pub video_streams: Arc<Mutex<HashMap<String, oneshot::Sender<()>>>>,
    pub provider: Arc<Mutex<Box<dyn idevice::provider::IdeviceProvider>>>,
    pub lockdown: Arc<Mutex<LockdownClient>>,
    pub ios_version: String,
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
    let mut state = APP_DEVICE_STATE.lock().await;
    if let Some(svc) = state.remove(udid) {
        if let Some(t) = &svc.heartbeat_task {
            t.abort();
        }

        let mut streams = svc.video_streams.lock().await;
        for (_url, tx) in streams.drain() {
            let _ = tx.send(());
        }

        image_cache::clear_for_udid(udid);

        println!("Removed device with UDID {}", udid);
    } else {
        eprintln!("Attempted to remove non-existent device with UDID {}", udid);
    }
}

/// Insert a device into the global state and, returns true if the device became wired
pub async fn insert_device(udid: impl Into<String>, services: DeviceServices) -> bool {
    let udid = udid.into();
    let mut state = APP_DEVICE_STATE.lock().await;
    if let Some(mut old) = state.insert(udid.clone(), services) {
        if let Some(task) = old.heartbeat_task.take() {
            eprintln!("device became wired - UDID {}", udid);
            task.abort();
            return true
        }
    }
    false
}

pub async fn insert_heartbeat_task(udid: impl Into<String>, task: Arc<JoinHandle<()>>) {
    let mut state = APP_DEVICE_STATE.lock().await;
    if let Some(svc) = state.get_mut(&udid.into()) {
        svc.heartbeat_task = Some(task);
    }
}