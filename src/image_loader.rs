use crate::RUNTIME;
use crate::device_ctx;
use crate::qt_threading::{QtThread, QtThreading};
use crate::utils::{
    AfcReader, MediaFileType, create_image_from_buffer, generate_thumbnail, heic_to_qimage,
    media_file_type,
};
use ::log::{debug, error};
use idevice::afc::AfcClient;
use idevice::afc::opcode::AfcFopenMode;
use macros::QtThreading;
use once_cell::sync::Lazy;
use priority_queue::PriorityQueue;
use qmetaobject::prelude::*;
use qttypes::{QImage, QString};
use std::cmp::Reverse;
use std::collections::HashMap;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU64, Ordering},
};
use tokio::{
    io::AsyncReadExt,
    sync::{Notify, Semaphore},
};
use tokio_util::sync::CancellationToken;

#[allow(non_snake_case)]
#[derive(Default, QObject, QtThreading)]
pub struct ImageLoader {
    base: qt_base_class!(trait QObject),

    thumbnailReady: qt_signal!(file_path: QString, row: u32, afc2: bool),
}

static POOL_SEM: Lazy<Arc<Semaphore>> = Lazy::new(|| Arc::new(Semaphore::new(10)));
static SCHEDULER: Lazy<Arc<Scheduler>> = Lazy::new(|| {
    let scheduler = Arc::new(Scheduler::new());
    let worker_scheduler = Arc::clone(&scheduler);
    RUNTIME.spawn(async move {
        worker_scheduler.run().await;
    });
    scheduler
});
static NEXT_SEQ: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Debug, Hash, Eq, PartialEq)]
struct JobKey {
    udid: String,
    path: String,
    afc2: bool,
    width: u32,
    height: u32,
}

struct JobPayload {
    row: u32,
    path_for_qt: QString,
    qt_thread: QtThread<ImageLoader>,
}

struct QueueState {
    pq: PriorityQueue<JobKey, (u32, Reverse<u64>)>,
    payloads: HashMap<JobKey, JobPayload>,
    in_flight: HashMap<JobKey, CancellationToken>,
}

struct Scheduler {
    state: Mutex<QueueState>,
    notify: Notify,
}

impl Scheduler {
    fn new() -> Self {
        Self {
            state: Mutex::new(QueueState {
                pq: PriorityQueue::new(),
                payloads: HashMap::new(),
                in_flight: HashMap::new(),
            }),
            notify: Notify::new(),
        }
    }

    fn enqueue(&self, key: JobKey, payload: JobPayload, row: u32) {
        let seq = NEXT_SEQ.fetch_add(1, Ordering::Relaxed);
        let priority = (row, Reverse(seq));

        {
            let mut guard = self.state.lock().expect("scheduler mutex poisoned");
            if guard.in_flight.contains_key(&key) {
                return;
            }

            guard.payloads.insert(key.clone(), payload);

            if guard.pq.get_priority(&key).is_some() {
                guard.pq.change_priority(&key, priority);
            } else {
                guard.pq.push(key, priority);
            }
        }

        self.notify.notify_one();
    }

    fn pop_next(&self) -> Option<(JobKey, JobPayload, CancellationToken)> {
        let mut guard = self.state.lock().expect("scheduler mutex poisoned");
        let (key, _) = guard.pq.pop()?;
        let payload = guard.payloads.remove(&key)?;
        let cancellation = CancellationToken::new();
        guard.in_flight.insert(key.clone(), cancellation.clone());
        Some((key, payload, cancellation))
    }

    fn finish(&self, key: &JobKey) {
        self.state
            .lock()
            .expect("scheduler mutex poisoned")
            .in_flight
            .remove(key);
    }

    fn cancel_for_udid(&self, udid: &str) {
        let (queued_count, active_cancellations) = {
            let mut guard = self.state.lock().expect("scheduler mutex poisoned");
            let queued_keys: Vec<_> = guard
                .payloads
                .keys()
                .filter(|key| key.udid == udid)
                .cloned()
                .collect();

            for key in &queued_keys {
                guard.pq.remove(key);
                guard.payloads.remove(key);
            }

            let active_cancellations = guard
                .in_flight
                .iter()
                .filter(|(key, _)| key.udid == udid)
                .map(|(_, cancellation)| cancellation.clone())
                .collect::<Vec<_>>();

            (queued_keys.len(), active_cancellations)
        };

        for cancellation in &active_cancellations {
            cancellation.cancel();
        }

        debug!(
            "Cancelled {queued_count} queued and {} active thumbnail jobs for {udid}",
            active_cancellations.len()
        );
    }

    async fn run(self: Arc<Self>) {
        loop {
            let Some((key, payload, cancellation)) = self.pop_next() else {
                self.notify.notified().await;
                continue;
            };

            let permit = tokio::select! {
                _ = cancellation.cancelled() => {
                    self.finish(&key);
                    continue;
                }
                result = POOL_SEM.clone().acquire_owned() => {
                    match result {
                        Ok(permit) => permit,
                        Err(err) => {
                            self.finish(&key);
                            error!("image_loader: semaphore acquire failed: {err}");
                            continue;
                        }
                    }
                }
            };

            let scheduler = Arc::clone(&self);
            RUNTIME.spawn(async move {
                let _permit = permit;
                let result: anyhow::Result<()> = async {
                    if cancellation.is_cancelled() {
                        return Ok(());
                    }

                    let device = device_ctx::get_device(key.udid.as_str()).await?;
                    let connection_id = device.connection_id;
                    let afc_arc = if key.afc2 {
                        device.afc2.ok_or_else(|| {
                            anyhow::anyhow!("AFC2 is unavailable for device {}", key.udid)
                        })?
                    } else {
                        device.afc
                    };

                    let img = match media_file_type(&key.path) {
                        MediaFileType::Video => {
                            // FIXME: can we do something better here ?
                            let reader =
                                AfcReader::new(key.udid.clone(), key.path.clone(), afc_arc);

                            // let reader_for_block = reader;
                            let f_size = reader.get_size().await;
                            if cancellation.is_cancelled() {
                                return Ok(());
                            }
                            if !(f_size > 0) {
                                anyhow::bail!("File size is invalid for {}", key.path);
                            };

                            tokio::task::spawn_blocking(move || {
                                generate_thumbnail(
                                    &reader,
                                    f_size, // FIXME: use consts for sizes
                                    key.width as i32,
                                    key.height as i32,
                                )
                            })
                            .await
                            .unwrap_or_default()
                        }
                        MediaFileType::Heic => {
                            let mut afc = afc_arc.lock().await;
                            if cancellation.is_cancelled() {
                                return Ok(());
                            }

                            let mut fd = afc.open(&key.path, AfcFopenMode::RdOnly).await?;
                            let read_result = fd.read_entire().await;
                            let close_result = fd.close().await;
                            let buf = read_result?;
                            close_result?;

                            if cancellation.is_cancelled() {
                                return Ok(());
                            }

                            heic_to_qimage(&buf)
                        }
                        MediaFileType::Image => {
                            let mut afc = afc_arc.lock().await;
                            if cancellation.is_cancelled() {
                                return Ok(());
                            }

                            file_to_image(&mut afc, &key.path, key.width, key.height).await
                        }
                        MediaFileType::Unsupported => {
                            anyhow::bail!("Unsupported media file {}", key.path);
                        }
                    };

                    if cancellation.is_cancelled()
                        || device_ctx::get_device_for_connection_opt(
                            key.udid.as_str(),
                            connection_id,
                        )
                        .await
                        .is_none()
                    {
                        return Ok(());
                    }

                    crate::image_cache::insert(
                        &key.udid, &key.path, key.afc2, key.width, key.height, img,
                    );

                    let row = payload.row;
                    let path_for_qt = payload.path_for_qt;
                    let qt_thread = payload.qt_thread;
                    let afc2 = key.afc2;

                    qt_thread.queue(move |backend_qobj| {
                        backend_qobj.thumbnailReady(path_for_qt, row, afc2);
                    });

                    Ok(())
                }
                .await;

                scheduler.finish(&key);

                if let Err(err) = result {
                    error!("image_loader: thumbnail job failed: {err}");
                }
            });
        }
    }
}

pub fn cancel_for_udid(udid: &str) {
    if let Some(scheduler) = Lazy::get(&SCHEDULER) {
        scheduler.cancel_for_udid(udid);
    }
}

//FIXME: move
async fn file_to_image(afc: &mut AfcClient, path: &str, width: u32, height: u32) -> QImage {
    let mut buf = Vec::new();

    let mut fd = match afc.open(path, AfcFopenMode::RdOnly).await {
        Ok(f) => f,
        Err(e) => {
            error!("file_to_image: failed to open {path}: {e}");
            return QImage::default();
        }
    };

    // FIXME: optimize chunk
    let mut chunk = vec![0u8; crate::io_manager::DEFAULT_CHUNK_SIZE];

    loop {
        let n = match fd.read(&mut chunk).await {
            Ok(n) => n,
            Err(e) => {
                error!("file_to_image: failed to read {path}: {e}");
                buf.clear();
                break;
            }
        };
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&chunk[..n]);
    }
    fd.close().await.ok();

    create_image_from_buffer(&buf, width, height)
}

impl ImageLoader {
    pub fn request_thumbnail(
        &self,
        udid: QString,
        file_path: QString,
        afc2: bool,
        row: u32,
        width: u32,
        height: u32,
    ) {
        let udid_string = udid.to_string();
        let path_string = file_path.to_string();

        let key = JobKey {
            udid: udid_string,
            path: path_string,
            afc2,
            width,
            height,
        };

        let payload = JobPayload {
            row,
            path_for_qt: file_path.clone(),
            qt_thread: self.qt_thread(),
        };

        SCHEDULER.enqueue(key, payload, row);
    }
}
