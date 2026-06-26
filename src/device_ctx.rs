use idevice::{
    afc::AfcClient, diagnostics_relay::DiagnosticsRelayClient, lockdown::LockdownClient,
};
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;

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

// FIXME: shouldn't be public
pub static APP_DEVICE_STATE: Lazy<Mutex<HashMap<String, DeviceServices>>> =
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
