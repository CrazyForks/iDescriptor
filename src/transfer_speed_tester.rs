use crate::qt_threading::{QtThread, QtThreading};
use crate::utils::{PUBLIC_STAGING, ensure_public_staging};
use crate::{RUNTIME, qvariantmap_insert};
use anyhow::{Context, anyhow};
use idevice::afc::{AfcClient, opcode::AfcFopenMode};
use log::{debug, error, info, warn};
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::QVariantMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::Mutex;
use uuid::Uuid;

const MIB: u64 = 1024 * 1024;
const CHUNK_SIZE: usize = MIB as usize;
const STORAGE_SAFETY_MARGIN: u64 = 16 * MIB;
const UPDATE_INTERVAL: Duration = Duration::from_millis(200);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Phase {
    Idle,
    Upload,
    Download,
    Complete,
    Error,
}

impl Phase {
    fn as_str(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Upload => "upload",
            Self::Download => "download",
            Self::Complete => "complete",
            Self::Error => "error",
        }
    }
}

#[derive(Clone, Debug)]
struct TransferState {
    running: bool,
    phase: Phase,
    total_bytes: u64,
    upload_bytes: u64,
    download_bytes: u64,
    upload_progress: f64,
    download_progress: f64,
    current_mibps: f64,
    upload_mibps: f64,
    download_mibps: f64,
    upload_seconds: f64,
    download_seconds: f64,
    error: &'static str,
}

impl Default for TransferState {
    fn default() -> Self {
        Self {
            running: false,
            phase: Phase::Idle,
            total_bytes: 0,
            upload_bytes: 0,
            download_bytes: 0,
            upload_progress: 0.0,
            download_progress: 0.0,
            current_mibps: 0.0,
            upload_mibps: 0.0,
            download_mibps: 0.0,
            upload_seconds: 0.0,
            download_seconds: 0.0,
            error: "",
        }
    }
}

impl TransferState {
    fn to_map(&self) -> QVariantMap {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "running", self.running);
        qvariantmap_insert!(state, "phase", QString::from(self.phase.as_str()));
        qvariantmap_insert!(state, "totalBytes", self.total_bytes as i64);
        qvariantmap_insert!(state, "uploadBytes", self.upload_bytes as i64);
        qvariantmap_insert!(state, "downloadBytes", self.download_bytes as i64);
        qvariantmap_insert!(state, "uploadProgress", self.upload_progress);
        qvariantmap_insert!(state, "downloadProgress", self.download_progress);
        qvariantmap_insert!(state, "currentMiBps", self.current_mibps);
        qvariantmap_insert!(state, "uploadMiBps", self.upload_mibps);
        qvariantmap_insert!(state, "downloadMiBps", self.download_mibps);
        qvariantmap_insert!(state, "uploadSeconds", self.upload_seconds);
        qvariantmap_insert!(state, "downloadSeconds", self.download_seconds);
        qvariantmap_insert!(state, "error", QString::from(self.error));
        state
    }
}

#[derive(Debug)]
struct TransferResult {
    upload_mibps: f64,
    download_mibps: f64,
    upload_seconds: f64,
    download_seconds: f64,
}

#[derive(Debug)]
enum RunFailure {
    Cancelled,
    Error(anyhow::Error),
}

impl From<anyhow::Error> for RunFailure {
    fn from(error: anyhow::Error) -> Self {
        Self::Error(error)
    }
}

#[allow(non_snake_case)]
#[derive(QObject, QtThreading)]
pub struct TransferSpeedTester {
    base: qt_base_class!(trait QObject),
    state: qt_property!(QVariantMap; NOTIFY stateChanged),
    stateChanged: qt_signal!(),
    start_test: qt_method!(fn(&mut self, size_mib: i32)),
    cancel_test: qt_method!(fn(&mut self)),
    afc: Arc<Mutex<AfcClient>>,
    udid: String,
    cancel_flag: Arc<AtomicBool>,
    running: bool,
}

impl TransferSpeedTester {
    pub fn new(afc: Arc<Mutex<AfcClient>>, udid: String) -> Self {
        Self {
            base: Default::default(),
            state: TransferState::default().to_map(),
            stateChanged: Default::default(),
            start_test: Default::default(),
            cancel_test: Default::default(),
            afc,
            udid,
            cancel_flag: Arc::new(AtomicBool::new(false)),
            running: false,
        }
    }

    fn set_state(&mut self, state: TransferState) {
        self.running = state.running;
        self.state = state.to_map();
        self.stateChanged();
    }

    fn start_test(&mut self, size_mib: i32) {
        if self.running {
            debug!(
                "TransferSpeedTester: ignoring concurrent start for {}",
                self.udid
            );
            return;
        }

        let Some(total_bytes) = payload_bytes(size_mib) else {
            let state = TransferState {
                phase: Phase::Error,
                error: "invalid_size",
                ..Default::default()
            };
            self.set_state(state);
            return;
        };

        self.cancel_flag.store(false, Ordering::Relaxed);
        self.set_state(TransferState {
            running: true,
            phase: Phase::Upload,
            total_bytes,
            ..Default::default()
        });

        let afc = self.afc.clone();
        let cancel_flag = self.cancel_flag.clone();
        let qt_thread = self.qt_thread();
        let udid = self.udid.clone();

        info!("TransferSpeedTester: starting {size_mib} MiB test for {udid}");
        RUNTIME.spawn(async move {
            let remote_path = format!(
                "{PUBLIC_STAGING}/.idescriptor-speed-test-{}.bin",
                Uuid::new_v4()
            );
            let mut afc = afc.lock().await;

            let run_result = run_transfer_test(
                &mut afc,
                &remote_path,
                total_bytes,
                &cancel_flag,
                &qt_thread,
            )
            .await;

            let cleanup_result = afc.remove(&remote_path).await;
            if let Err(cleanup_error) = &cleanup_result {
                warn!(
                    "TransferSpeedTester: failed to remove {remote_path} for {udid}: {cleanup_error}"
                );
            }

            if cancel_flag.load(Ordering::Relaxed) {
                info!("TransferSpeedTester: cancelled test for {udid}");
                queue_state(&qt_thread, TransferState::default());
                return;
            }

            match run_result {
                Ok(result) if cleanup_result.is_ok() => {
                    info!("TransferSpeedTester: completed test for {udid}");
                    queue_state(
                        &qt_thread,
                        TransferState {
                            phase: Phase::Complete,
                            total_bytes,
                            upload_bytes: total_bytes,
                            download_bytes: total_bytes,
                            upload_progress: 1.0,
                            download_progress: 1.0,
                            download_mibps: result.download_mibps,
                            upload_mibps: result.upload_mibps,
                            download_seconds: result.download_seconds,
                            upload_seconds: result.upload_seconds,
                            ..Default::default()
                        },
                    );
                }
                Ok(_) => {
                    queue_error(&qt_thread, "cleanup_failed");
                }
                Err(RunFailure::Cancelled) => {
                    info!("TransferSpeedTester: cancelled test for {udid}");
                    queue_state(&qt_thread, TransferState::default());
                }
                Err(RunFailure::Error(run_error)) => {
                    error!("TransferSpeedTester: test failed for {udid}: {run_error:#}");
                    queue_error(&qt_thread, classify_error(&run_error));
                }
            }
        });
    }

    fn cancel_test(&mut self) {
        if self.running {
            debug!(
                "TransferSpeedTester: cancellation requested for {}",
                self.udid
            );
            self.cancel_flag.store(true, Ordering::Relaxed);
        }
    }
}

impl Drop for TransferSpeedTester {
    fn drop(&mut self) {
        self.cancel_flag.store(true, Ordering::Relaxed);
    }
}

fn queue_state(qt_thread: &QtThread<TransferSpeedTester>, state: TransferState) {
    qt_thread.queue(move |tester| tester.set_state(state));
}

fn queue_error(qt_thread: &QtThread<TransferSpeedTester>, error_code: &'static str) {
    queue_state(
        qt_thread,
        TransferState {
            phase: Phase::Error,
            error: error_code,
            ..Default::default()
        },
    );
}

async fn run_transfer_test(
    afc: &mut AfcClient,
    remote_path: &str,
    total_bytes: u64,
    cancel_flag: &AtomicBool,
    qt_thread: &QtThread<TransferSpeedTester>,
) -> Result<TransferResult, RunFailure> {
    ensure_not_cancelled(cancel_flag)?;
    ensure_public_staging(afc)
        .await
        .context("failed to prepare PublicStaging")?;

    let device_info = afc
        .get_device_info()
        .await
        .context("failed to query device storage")?;
    let required_bytes = total_bytes.saturating_add(STORAGE_SAFETY_MARGIN);
    if (device_info.free_bytes as u64) < required_bytes {
        return Err(RunFailure::Error(anyhow!(
            "insufficient storage: need {required_bytes} bytes, have {}",
            device_info.free_bytes
        )));
    }

    let payload = deterministic_payload();
    let upload = transfer_upload(
        afc,
        remote_path,
        total_bytes,
        &payload,
        cancel_flag,
        qt_thread,
    )
    .await?;

    ensure_not_cancelled(cancel_flag)?;
    let remote_info = afc
        .get_file_info(remote_path)
        .await
        .context("failed to verify uploaded payload")?;
    if remote_info.size as u64 != total_bytes {
        return Err(RunFailure::Error(anyhow!(
            "uploaded size mismatch: expected {total_bytes}, found {}",
            remote_info.size
        )));
    }

    let download = transfer_download(
        afc,
        remote_path,
        total_bytes,
        cancel_flag,
        qt_thread,
        upload,
    )
    .await?;

    Ok(TransferResult {
        upload_mibps: throughput_mibps(total_bytes, upload),
        download_mibps: throughput_mibps(total_bytes, download),
        upload_seconds: upload.as_secs_f64(),
        download_seconds: download.as_secs_f64(),
    })
}

async fn transfer_upload(
    afc: &mut AfcClient,
    remote_path: &str,
    total_bytes: u64,
    payload: &[u8],
    cancel_flag: &AtomicBool,
    qt_thread: &QtThread<TransferSpeedTester>,
) -> Result<Duration, RunFailure> {
    let mut remote = afc
        .open(remote_path, AfcFopenMode::WrOnly)
        .await
        .context("failed to open speed-test payload for upload")?;
    let started = Instant::now();
    let mut transferred = 0_u64;
    let mut last_update = Instant::now();
    let mut failure = None;

    while transferred < total_bytes {
        if cancel_flag.load(Ordering::Relaxed) {
            failure = Some(RunFailure::Cancelled);
            break;
        }

        let remaining = (total_bytes - transferred) as usize;
        let chunk_len = remaining.min(payload.len());
        if let Err(err) = remote.write_all(&payload[..chunk_len]).await {
            failure = Some(RunFailure::Error(anyhow!(err).context("AFC upload failed")));
            break;
        }
        transferred += chunk_len as u64;

        if last_update.elapsed() >= UPDATE_INTERVAL || transferred == total_bytes {
            emit_progress(
                qt_thread,
                Phase::Upload,
                transferred,
                total_bytes,
                started.elapsed(),
                0.0,
                0.0,
            );
            last_update = Instant::now();
        }
    }

    let close_result = remote.close().await;
    if let Some(failure) = failure {
        if let Err(close_error) = close_result {
            warn!("TransferSpeedTester: failed to close upload handle: {close_error}");
        }
        return Err(failure);
    }
    close_result.context("failed to close uploaded payload")?;

    if transferred != total_bytes {
        return Err(RunFailure::Error(anyhow!(
            "upload byte mismatch: expected {total_bytes}, transferred {transferred}"
        )));
    }
    Ok(started.elapsed())
}

async fn transfer_download(
    afc: &mut AfcClient,
    remote_path: &str,
    total_bytes: u64,
    cancel_flag: &AtomicBool,
    qt_thread: &QtThread<TransferSpeedTester>,
    upload_duration: Duration,
) -> Result<Duration, RunFailure> {
    let mut remote = afc
        .open(remote_path, AfcFopenMode::RdOnly)
        .await
        .context("failed to open speed-test payload for download")?;
    let mut buffer = vec![0_u8; CHUNK_SIZE];
    let started = Instant::now();
    let mut transferred = 0_u64;
    let mut last_update = Instant::now();
    let mut failure = None;

    emit_progress(
        qt_thread,
        Phase::Download,
        0,
        total_bytes,
        started.elapsed(),
        throughput_mibps(total_bytes, upload_duration),
        upload_duration.as_secs_f64(),
    );

    while transferred < total_bytes {
        if cancel_flag.load(Ordering::Relaxed) {
            failure = Some(RunFailure::Cancelled);
            break;
        }

        let remaining = (total_bytes - transferred) as usize;
        let read_len = remaining.min(buffer.len());
        match remote.read(&mut buffer[..read_len]).await {
            Ok(0) => {
                failure = Some(RunFailure::Error(anyhow!(
                    "download ended early after {transferred} of {total_bytes} bytes"
                )));
                break;
            }
            Ok(read) => transferred += read as u64,
            Err(err) => {
                failure = Some(RunFailure::Error(
                    anyhow!(err).context("AFC download failed"),
                ));
                break;
            }
        }

        if last_update.elapsed() >= UPDATE_INTERVAL || transferred == total_bytes {
            emit_progress(
                qt_thread,
                Phase::Download,
                transferred,
                total_bytes,
                started.elapsed(),
                throughput_mibps(total_bytes, upload_duration),
                upload_duration.as_secs_f64(),
            );
            last_update = Instant::now();
        }
    }

    let close_result = remote.close().await;
    if let Some(failure) = failure {
        if let Err(close_error) = close_result {
            warn!("TransferSpeedTester: failed to close download handle: {close_error}");
        }
        return Err(failure);
    }
    close_result.context("failed to close downloaded payload")?;

    if transferred != total_bytes {
        return Err(RunFailure::Error(anyhow!(
            "download byte mismatch: expected {total_bytes}, transferred {transferred}"
        )));
    }
    Ok(started.elapsed())
}

fn emit_progress(
    qt_thread: &QtThread<TransferSpeedTester>,
    phase: Phase,
    transferred: u64,
    total_bytes: u64,
    elapsed: Duration,
    upload_mibps: f64,
    upload_seconds: f64,
) {
    let phase_progress = phase_progress(transferred, total_bytes);
    let (upload_bytes, download_bytes, upload_progress, download_progress) = match phase {
        Phase::Upload => (transferred, 0, phase_progress, 0.0),
        Phase::Download => (total_bytes, transferred, 1.0, phase_progress),
        Phase::Complete => (total_bytes, total_bytes, 1.0, 1.0),
        Phase::Idle | Phase::Error => (0, 0, 0.0, 0.0),
    };
    queue_state(
        qt_thread,
        TransferState {
            running: true,
            phase,
            total_bytes,
            upload_bytes,
            download_bytes,
            upload_progress,
            download_progress,
            current_mibps: throughput_mibps(transferred, elapsed),
            upload_mibps,
            upload_seconds,
            ..Default::default()
        },
    );
}

fn ensure_not_cancelled(cancel_flag: &AtomicBool) -> Result<(), RunFailure> {
    if cancel_flag.load(Ordering::Relaxed) {
        Err(RunFailure::Cancelled)
    } else {
        Ok(())
    }
}

fn payload_bytes(size_mib: i32) -> Option<u64> {
    matches!(size_mib, 32 | 128 | 512).then_some(size_mib as u64 * MIB)
}

fn deterministic_payload() -> Vec<u8> {
    (0..CHUNK_SIZE)
        .map(|index| ((index.wrapping_mul(31).wrapping_add(17)) & 0xff) as u8)
        .collect()
}

fn throughput_mibps(bytes: u64, elapsed: Duration) -> f64 {
    let seconds = elapsed.as_secs_f64();
    if seconds > 0.0 {
        bytes as f64 / MIB as f64 / seconds
    } else {
        0.0
    }
}

fn phase_progress(transferred: u64, total_bytes: u64) -> f64 {
    if total_bytes == 0 {
        return 0.0;
    }
    transferred.min(total_bytes) as f64 / total_bytes as f64
}

fn classify_error(error: &anyhow::Error) -> &'static str {
    if error.to_string().contains("insufficient storage") {
        "insufficient_storage"
    } else {
        "afc_failed"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_supported_payload_sizes() {
        assert_eq!(payload_bytes(32), Some(32 * MIB));
        assert_eq!(payload_bytes(128), Some(128 * MIB));
        assert_eq!(payload_bytes(512), Some(512 * MIB));
        assert_eq!(payload_bytes(0), None);
        assert_eq!(payload_bytes(64), None);
    }

    #[test]
    fn each_phase_has_independent_progress() {
        let total = 128 * MIB;
        assert_eq!(phase_progress(0, total), 0.0);
        assert_eq!(phase_progress(total / 2, total), 0.5);
        assert_eq!(phase_progress(total, total), 1.0);
        assert_eq!(phase_progress(total * 2, total), 1.0);
    }

    #[test]
    fn throughput_uses_binary_megabytes() {
        let speed = throughput_mibps(128 * MIB, Duration::from_secs(2));
        assert!((speed - 64.0).abs() < f64::EPSILON);
        assert!((speed * 8.388_608 - 536.870_912).abs() < 0.000_001);
    }

    #[test]
    fn deterministic_chunk_has_expected_size_and_content() {
        let payload = deterministic_payload();
        assert_eq!(payload.len(), CHUNK_SIZE);
        assert_eq!(payload[0], 17);
        assert_eq!(payload[1], 48);
        assert_eq!(payload[CHUNK_SIZE - 1], 242);
    }

    #[test]
    fn cancellation_is_observed() {
        let flag = AtomicBool::new(false);
        assert!(ensure_not_cancelled(&flag).is_ok());
        flag.store(true, Ordering::Relaxed);
        assert!(matches!(
            ensure_not_cancelled(&flag),
            Err(RunFailure::Cancelled)
        ));
    }
}
