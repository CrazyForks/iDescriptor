use crate::RUNTIME;
use crate::device_ctx;
use crate::qt_threading::{QtThread, QtThreading};
use crate::utils::{
    AfcReader, MediaFileType, create_image_from_buffer, generate_thumbnail, heic_to_qimage,
    media_file_type,
};
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
    atomic::{AtomicBool, AtomicU64, Ordering},
};
use tokio::{
    io::AsyncReadExt,
    sync::{Notify, Semaphore},
};

#[derive(Default, QObject, QtThreading)]
pub struct ImageLoader {
    base: qt_base_class!(trait QObject),

    thumbnailReady: qt_signal!(file_path: QString, row: u32, afc2: bool),
}

static POOL_SEM: Lazy<Arc<Semaphore>> = Lazy::new(|| Arc::new(Semaphore::new(10)));
static SCHEDULER: Lazy<Arc<Scheduler>> = Lazy::new(|| Arc::new(Scheduler::new()));
static WORKER_STARTED: AtomicBool = AtomicBool::new(false);
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
            }),
            notify: Notify::new(),
        }
    }

    fn enqueue(&self, key: JobKey, payload: JobPayload, row: u32) {
        let seq = NEXT_SEQ.fetch_add(1, Ordering::Relaxed);
        let priority = (row, Reverse(seq));

        {
            let mut guard = self.state.lock().expect("scheduler mutex poisoned");
            guard.payloads.insert(key.clone(), payload);

            if guard.pq.get_priority(&key).is_some() {
                guard.pq.change_priority(&key, priority);
            } else {
                guard.pq.push(key, priority);
            }
        }

        self.notify.notify_one();
    }

    fn pop_next(&self) -> Option<(JobKey, JobPayload)> {
        let mut guard = self.state.lock().expect("scheduler mutex poisoned");
        let (key, _) = guard.pq.pop()?;
        let payload = guard.payloads.remove(&key)?;
        Some((key, payload))
    }
}

fn ensure_worker_started() {
    if WORKER_STARTED
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_ok()
    {
        // TODO: use std::thread ?
        RUNTIME.spawn(async {
            loop {
                let Some((key, payload)) = SCHEDULER.pop_next() else {
                    SCHEDULER.notify.notified().await;
                    continue;
                };

                let permit = match POOL_SEM.clone().acquire_owned().await {
                    Ok(p) => p,
                    Err(e) => {
                        eprintln!("image_loader: semaphore acquire failed: {e}");
                        continue;
                    }
                };

                RUNTIME.spawn(async move {
                    let _permit = permit;

                    let res: anyhow::Result<()> = async {
                        let device = device_ctx::get_device(key.udid.as_str()).await?;
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
                                let mut fd = afc.open(&key.path, AfcFopenMode::RdOnly).await?;
                                let buf = fd.read_entire().await?;
                                println!("Read {} bytes from {}", buf.len(), key.path);
                                let img = heic_to_qimage(&buf);
                                fd.close().await.ok();
                                img
                            }
                            MediaFileType::Image => {
                                let mut afc = afc_arc.lock().await;
                                file_to_image(&mut afc, &key.path, key.width, key.height).await
                            }
                            MediaFileType::Unsupported => {
                                anyhow::bail!("Unsupported media file {}", key.path);
                            }
                        };

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
                });
            }
        });
    }
}

// FIXME: move or remove
async fn file_to_buffer(afc: &mut AfcClient, path: String) -> Vec<u8> {
    let mut buf: Vec<u8> = Vec::new();

    let mut fd = match afc.open(path, AfcFopenMode::RdOnly).await {
        Ok(f) => f,
        Err(e) => {
            // eprintln!("file_to_buffer: failed to open {path}: {e}");
            return buf;
        }
    };

    let mut chunk = vec![0u8; 8192];

    loop {
        let n = match fd.read(&mut chunk).await {
            Ok(n) => n,
            Err(e) => {
                // eprintln!("file_to_buffer: failed to read {path}: {e}");
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
    buf
}

//FIXME: move
async fn file_to_image(afc: &mut AfcClient, path: &str, width: u32, height: u32) -> QImage {
    let mut buf = Vec::new();

    let mut fd = match afc.open(path, AfcFopenMode::RdOnly).await {
        Ok(f) => f,
        Err(e) => {
            // eprintln!("file_to_buffer: failed to open {path}: {e}");
            return QImage::default();
        }
    };

    // FIXME: optimize chunk
    let mut chunk = vec![0u8; 1024 * 1024]; // 1MB

    loop {
        let n = match fd.read(&mut chunk).await {
            Ok(n) => n,
            Err(e) => {
                // eprintln!("file_to_buffer: failed to read {path}: {e}");
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
        ensure_worker_started();
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
