// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

use crate::RUNTIME;
use crate::device_ctx;
use crate::qt_threading::{QtThread, QtThreading};
use crate::utils::{
    AfcReader, MediaFileType, create_image_from_buffer, generate_thumbnail, heic_to_qimage,
    media_file_type, scale_image_to_fit,
};
use ::log::{debug, error};
use anyhow::Context;
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
static DECODE_SEM: Lazy<Arc<Semaphore>> = Lazy::new(|| Arc::new(Semaphore::new(10)));
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

struct InFlightJob {
    cancellation: CancellationToken,
    payloads: Vec<JobPayload>,
}

struct QueueState {
    pq: PriorityQueue<JobKey, (u32, Reverse<u64>)>,
    payloads: HashMap<JobKey, Vec<JobPayload>>,
    in_flight: HashMap<JobKey, InFlightJob>,
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
            if let Some(job) = guard.in_flight.get_mut(&key) {
                if !job.cancellation.is_cancelled() {
                    job.payloads.push(payload);
                }
                return;
            }

            guard.payloads.entry(key.clone()).or_default().push(payload);

            if guard.pq.get_priority(&key).is_some() {
                guard.pq.change_priority(&key, priority);
            } else {
                guard.pq.push(key, priority);
            }
        }

        self.notify.notify_one();
    }

    fn pop_next(&self) -> Option<(JobKey, CancellationToken)> {
        let mut guard = self.state.lock().expect("scheduler mutex poisoned");
        let (key, _) = guard.pq.pop()?;
        let payloads = guard.payloads.remove(&key)?;
        let cancellation = CancellationToken::new();
        guard.in_flight.insert(
            key.clone(),
            InFlightJob {
                cancellation: cancellation.clone(),
                payloads,
            },
        );
        Some((key, cancellation))
    }

    fn finish(&self, key: &JobKey) -> Vec<JobPayload> {
        self.state
            .lock()
            .expect("scheduler mutex poisoned")
            .in_flight
            .remove(key)
            .map(|job| job.payloads)
            .unwrap_or_default()
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
                .map(|(_, job)| job.cancellation.clone())
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
            let Some((key, cancellation)) = self.pop_next() else {
                self.notify.notified().await;
                continue;
            };

            let permit = tokio::select! {
                _ = cancellation.cancelled() => {
                    let _ = self.finish(&key);
                    continue;
                }
                result = POOL_SEM.clone().acquire_owned() => {
                    match result {
                        Ok(permit) => permit,
                        Err(err) => {
                            let _ = self.finish(&key);
                            error!("image_loader: semaphore acquire failed: {err}");
                            continue;
                        }
                    }
                }
            };

            let scheduler = Arc::clone(&self);
            RUNTIME.spawn(async move {
                let _permit = permit;
                let result: anyhow::Result<bool> = async {
                    if cancellation.is_cancelled() {
                        return Ok(false);
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

                            let f_size = reader.get_size().await?;
                            if cancellation.is_cancelled() {
                                return Ok(false);
                            }
                            if !(f_size > 0) {
                                anyhow::bail!("File size is invalid for {}", key.path);
                            };

                            let Some(img) = decode_image(&cancellation, move || {
                                generate_thumbnail(
                                    &reader,
                                    f_size,
                                    key.width as i32,
                                    key.height as i32,
                                )
                            })
                            .await?
                            else {
                                return Ok(false);
                            };
                            img
                        }
                        MediaFileType::Heic => {
                            let buf = {
                                let mut afc = afc_arc.lock().await;
                                if cancellation.is_cancelled() {
                                    return Ok(false);
                                }

                                file_to_buffer(&mut afc, &key.path).await?
                            };

                            if cancellation.is_cancelled() {
                                return Ok(false);
                            }

                            let width = key.width;
                            let height = key.height;
                            let Some(img) = decode_image(&cancellation, move || {
                                scale_image_to_fit(heic_to_qimage(&buf), width, height)
                            })
                            .await?
                            else {
                                return Ok(false);
                            };
                            img
                        }
                        MediaFileType::Image => {
                            let buf = {
                                let mut afc = afc_arc.lock().await;
                                if cancellation.is_cancelled() {
                                    return Ok(false);
                                }

                                file_to_buffer(&mut afc, &key.path).await?
                            };

                            if cancellation.is_cancelled() {
                                return Ok(false);
                            }

                            let width = key.width;
                            let height = key.height;
                            let Some(img) = decode_image(&cancellation, move || {
                                create_image_from_buffer(&buf, width, height)
                            })
                            .await?
                            else {
                                return Ok(false);
                            };
                            img
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
                        return Ok(false);
                    }

                    crate::image_cache::insert(
                        &key.udid, &key.path, key.afc2, key.width, key.height, img,
                    );

                    Ok(true)
                }
                .await;

                let payloads = scheduler.finish(&key);
                match result {
                    Ok(true) => {
                        let afc2 = key.afc2;
                        for payload in payloads {
                            let row = payload.row;
                            let path_for_qt = payload.path_for_qt;
                            payload.qt_thread.queue(move |backend_qobj| {
                                backend_qobj.thumbnailReady(path_for_qt, row, afc2);
                            });
                        }
                    }
                    Ok(false) => {}
                    Err(err) => {
                        error!("image_loader: thumbnail job failed: {err}");
                    }
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

async fn decode_image<F>(
    cancellation: &CancellationToken,
    decode: F,
) -> anyhow::Result<Option<QImage>>
where
    F: FnOnce() -> QImage + Send + 'static,
{
    let permit = tokio::select! {
        _ = cancellation.cancelled() => return Ok(None),
        result = DECODE_SEM.clone().acquire_owned() => {
            result.context("image_loader: decoder semaphore is closed")?
        }
    };

    let image = tokio::task::spawn_blocking(move || {
        let _permit = permit;
        decode()
    })
    .await
    .context("image_loader: decoder task failed")?;

    Ok(Some(image))
}

async fn file_to_buffer(afc: &mut AfcClient, path: &str) -> anyhow::Result<Vec<u8>> {
    let mut buf = Vec::new();

    let mut fd = afc
        .open(path, AfcFopenMode::RdOnly)
        .await
        .with_context(|| format!("file_to_buffer: failed to open {path}"))?;

    let mut chunk = vec![0u8; crate::io_manager::DEFAULT_CHUNK_SIZE];

    loop {
        let n = match fd.read(&mut chunk).await {
            Ok(n) => n,
            Err(e) => {
                fd.close().await.ok();
                return Err(e).with_context(|| format!("file_to_buffer: failed to read {path}"));
            }
        };
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&chunk[..n]);
    }
    fd.close()
        .await
        .with_context(|| format!("file_to_buffer: failed to close {path}"))?;

    Ok(buf)
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
