use cxx_qt::Threading;
use cxx_qt_lib::{QByteArray, QImage, QString};
use idevice::afc::{self, AfcClient};

use crate::{APP_DEVICE_STATE, RUNTIME};
use core::ffi;
use idevice::afc::opcode::AfcFopenMode;
use once_cell::sync::Lazy;
use priority_queue::PriorityQueue;
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

#[cxx_qt::bridge]
mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        include!("cxx-qt-lib/qbytearray.h");
        include!("cxx-qt-lib/qimage.h");

        type QImage = cxx_qt_lib::QImage;
        type QString = cxx_qt_lib::QString;
        type QByteArray = cxx_qt_lib::QByteArray;
    }

    extern "RustQt" {
        #[qobject]
        type ImageBackend = super::ImageRustBackend;

        #[qinvokable]
        fn request_thumbnail(
            self: Pin<&mut ImageBackend>,
            udid: &QString,
            file_path: &QString,
            row: u32,
        );

        #[qsignal]
        fn thumbnail_ready(self: Pin<&mut ImageBackend>, file_path: QString, img: QImage, row: u32);
    }

    impl cxx_qt::Threading for ImageBackend {}
}

static POOL_SEM: Lazy<Arc<Semaphore>> = Lazy::new(|| Arc::new(Semaphore::new(10)));
static SCHEDULER: Lazy<Arc<Scheduler>> = Lazy::new(|| Arc::new(Scheduler::new()));
static WORKER_STARTED: AtomicBool = AtomicBool::new(false);
static NEXT_SEQ: AtomicU64 = AtomicU64::new(0);

#[derive(Default)]
pub struct ImageRustBackend;

#[derive(Clone, Debug, Hash, Eq, PartialEq)]
struct JobKey {
    udid: String,
    path: String,
}

struct JobPayload {
    row: u32,
    path_for_qt: QString,
    qt_thread: cxx_qt::CxxQtThread<qobject::ImageBackend>,
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

                    let afc_arc = {
                        let maybe_device = APP_DEVICE_STATE
                            .lock()
                            .await
                            .get(key.udid.as_str())
                            .cloned();

                        let device = match maybe_device {
                            Some(d) => d,
                            None => {
                                // eprintln!(
                                //     "image_loader::read_file_via_afc: device {udid} not found"
                                // );
                                return;
                            }
                        };

                        device.afc.clone()
                    };

                    let mut afc = afc_arc.lock().await;

                    let info = afc.get_file_info(&key.path).await;

                    let size = match info {
                        Ok(i) => i.size,
                        Err(_) => return,
                    };

                    drop(afc);

                    let mut img = QImage::default();
                    if is_video_file(&key.path) {
                        // FIXME: can we do something better here ?
                        let reader =
                            crate::bridge::AfcReader::new(key.udid.clone(), key.path.clone());

                        let reader_for_block = reader;
                        let size_for_block = size as i32;
                        img = tokio::task::spawn_blocking(move || {
                            crate::bridge::bridge::generate_thumbnail_with_reader(
                                &reader_for_block,
                                size_for_block,
                                // FIXME: sizes aren't respected
                                320,
                                240,
                            )
                        })
                        .await
                        .unwrap_or_default();
                    } else {
                        let mut afc = afc_arc.lock().await;
                        img = file_to_image(&mut afc, key.path).await;
                    }

                    let row = payload.row;
                    let path_for_qt = payload.path_for_qt;
                    let qt_thread = payload.qt_thread;

                    if let Err(e) = qt_thread.queue(move |mut backend_qobj| {
                        backend_qobj.thumbnail_ready(path_for_qt, img, row);
                    }) {
                        eprintln!("image_loader: failed to queue thumbnail_ready: {e}");
                    }
                });
            }
        });
    }
}
//FIXME:move to utils
fn is_video_file(path: &str) -> bool {
    let ext = path
        .rsplit_once('.')
        .map(|(_, e)| e.to_ascii_lowercase())
        .unwrap_or_default();

    matches!(
        ext.as_str(),
        "mp4"
            | "mov"
            | "m4v"
            | "avi"
            | "mkv"
            | "webm"
            | "flv"
            | "wmv"
            | "3gp"
            | "mpeg"
            | "mpg"
            | "ts"
            | "mts"
            | "m2ts"
    )
}

// async fn read_file_via_afc(udid: String, path: String) -> Vec<u8> {
//     let mut buf = Vec::new();
//     let mut chunk = vec![0u8; 8192];

//     loop {
//         let n = match fd.read(&mut chunk).await {
//             Ok(n) => n,
//             Err(e) => {
//                 eprintln!("image_loader::read_file_via_afc: failed to read {path}: {e}");
//                 buf.clear();
//                 break;
//             }
//         };

//         if n == 0 {
//             break;
//         }

//         buf.extend_from_slice(&chunk[..n]);
//     }

//     buf
// }

// FIXME: move or remove
async fn file_to_buffer(afc: &mut AfcClient, path: String) -> Vec<u8> {
    let mut buf = Vec::new();

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
async fn file_to_image(afc: &mut AfcClient, path: String) -> QImage {
    let mut buf = Vec::new();

    let mut fd = match afc.open(path, AfcFopenMode::RdOnly).await {
        Ok(f) => f,
        Err(e) => {
            // eprintln!("file_to_buffer: failed to open {path}: {e}");
            return QImage::default();
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

    match QImage::from_data(&buf, None) {
        Some(img) => img,
        None => QImage::default(),
    }
}

impl qobject::ImageBackend {
    fn request_thumbnail(
        self: ::std::pin::Pin<&mut Self>,
        udid: &QString,
        file_path: &QString,
        row: u32,
    ) {
        ensure_worker_started();

        let udid_string = udid.to_string();
        let path_string = file_path.to_string();

        let key = JobKey {
            udid: udid_string,
            path: path_string,
        };

        let payload = JobPayload {
            row,
            path_for_qt: file_path.clone(),
            qt_thread: self.qt_thread(),
        };

        SCHEDULER.enqueue(key, payload, row);
    }
}
