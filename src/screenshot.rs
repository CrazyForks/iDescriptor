use crate::{
    RUNTIME,
    device_ctx::get_device_opt,
    qt_threading::{QtThread, QtThreading},
};
use idevice::{IdeviceError, services::core_device_proxy::CoreDeviceProxy};
use idevice::{
    IdeviceService, RsdService, dvt::remote_server::RemoteServerClient, provider::IdeviceProvider,
    rsd::RsdHandshake,
};
use idevice::{dvt::screenshot::ScreenshotClient, screenshotr::ScreenshotService};
use macros::QtThreading;
use qmetaobject::prelude::*;
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use tokio::time::{Duration, Instant, sleep_until};

use log::debug;

const CAPTURE_FPS: u64 = 15;
const FRAME_INTERVAL: Duration =
    Duration::from_nanos((1_000_000_000 + CAPTURE_FPS - 1) / CAPTURE_FPS);

#[allow(non_snake_case)]
#[derive(QObject, Default, QtThreading)]
pub struct ScreenshotBackend {
    base: qt_base_class!(trait QObject),

    udid: qt_property!(QString; NOTIFY udid_changed),
    udid_changed: qt_signal!(),
    ios_version: qt_property!(u32; NOTIFY ios_version_changed),
    ios_version_changed: qt_signal!(),

    start_capture: qt_method!(fn(&mut self)),
    stop_capture: qt_method!(fn(&mut self)),

    screenshotCaptured: qt_signal!(data: QByteArray),
    initFailed: qt_signal!(reason: QString, need: QString),

    //TODO: do we really need this?
    capture_active: Arc<AtomicBool>,
}

impl ScreenshotBackend {
    fn start_capture(&mut self) {
        self.stop_capture();

        let qt_thread = self.qt_thread();
        let udid_str = self.udid.to_string();
        let ios_version = self.ios_version;
        let capture_active = Arc::new(AtomicBool::new(true));
        self.capture_active = capture_active.clone();

        println!(
            "Starting screenshot capture for device {}, iOS version {}",
            udid_str, ios_version
        );

        RUNTIME.spawn(async move {
            let device = match get_device_opt(udid_str.as_str()).await {
                Some(d) => d,
                None => {
                    eprintln!("screenshot: device {} not found", udid_str);
                    qt_thread.queue(move |backend_qobj| {
                        backend_qobj
                            .initFailed(QString::from("Device not found"), QString::default());
                    });
                    return;
                }
            };

            let provider_guard = device.provider.lock().await;

            if ios_version > 16 {
                run_capture_ios17_and_above(qt_thread, provider_guard.as_ref(), capture_active)
                    .await;
            } else {
                run_capture_ios16_and_lower(qt_thread, provider_guard.as_ref(), capture_active)
                    .await;
            }
        });
    }

    fn stop_capture(&mut self) {
        self.capture_active.store(false, Ordering::Relaxed);
    }
}

async fn run_capture_ios17_and_above(
    qt_thread: QtThread<ScreenshotBackend>,
    provider: &dyn IdeviceProvider,
    capture_active: Arc<AtomicBool>,
) {
    let proxy = match CoreDeviceProxy::connect(provider).await {
        Ok(p) => p,
        Err(e) => {
            eprintln!("screenshot CoreDeviceProxy connect failed: {e}");
            qt_thread.queue(move |b| {
                b.initFailed(
                    QString::from(format!("Failed to connect to CoreDeviceProxy: {e}")),
                    QString::default(),
                )
            });
            return;
        }
    };

    let rsd_port = proxy.tunnel_info().server_rsd_port;
    let mut adapter = match proxy.create_software_tunnel() {
        Ok(a) => a.to_async_handle(),
        Err(e) => {
            eprintln!("screenshot dvt tunnel err: {e}");
            qt_thread.queue(move |b| {
                b.initFailed(
                    QString::from(format!("Failed to create software tunnel: {e}")),
                    QString::default(),
                )
            });
            return;
        }
    };

    let stream = match adapter.connect(rsd_port).await {
        Ok(s) => s,
        Err(e) => {
            eprintln!("screenshot dvt connect err: {e}");
            qt_thread.queue(move |b| {
                b.initFailed(
                    QString::from(format!("Failed to connect to RSD port: {e}")),
                    QString::default(),
                )
            });
            return;
        }
    };

    let mut handshake = match RsdHandshake::new(stream).await {
        Ok(h) => h,
        Err(e) => {
            eprintln!("screenshot handshake err: {e}");
            qt_thread.queue(move |b| {
                b.initFailed(
                    QString::from(format!("Failed to complete RSD handshake: {e}")),
                    QString::default(),
                )
            });
            return;
        }
    };

    let mut remote_server = match RemoteServerClient::connect_rsd(&mut adapter, &mut handshake)
        .await
    {
        Ok(s) => s,
        Err(IdeviceError::ServiceNotFound) => {
            debug!(
                "Potentially developer mode disabled, prompting user to enable developer mode on device"
            );
            qt_thread.queue(move |b| {
                b.initFailed(
                    QString::from("Remote Server service not found on device"),
                    QString::from("dev-mode"),
                )
            });
            return;
        }
        Err(e) => {
            eprintln!("screenshot remote err: {e}");
            qt_thread.queue(move |b| {
                b.initFailed(
                    QString::from(format!("Failed to connect to Remote Server: {e}")),
                    QString::default(),
                )
            });
            return;
        }
    };

    if let Err(e) = remote_server.read_message(0).await {
        eprintln!("screenshot read_message err: {e}");
        qt_thread.queue(move |b| {
            b.initFailed(
                QString::from(format!("Failed to read initial message: {e}")),
                QString::default(),
            )
        });
        return;
    }

    // FIXME: not working fine for some reason
    match ScreenshotClient::new(&mut remote_server).await {
        Ok(mut client) => {
            while capture_active.load(Ordering::Relaxed) {
                let frame_started = Instant::now();
                tokio::select! {
                    res = client.take_screenshot() => {
                        match res {
                            Ok(b) => {
                                qt_thread.queue(move |backend| {
                                    backend.screenshotCaptured(QByteArray::from(b.as_slice()))
                                });
                            }
                            Err(e) => {
                                eprintln!("screenshot take err: {e}");
                                qt_thread.queue(move |b| {
                                    b.initFailed(
                                        QString::from(format!("Failed to take screenshot: {e}")),
                                        QString::default(),
                                    )
                                });
                                return;
                            }
                        }
                    }
                    _ = tokio::time::sleep(std::time::Duration::from_secs(1)) => {
                        eprintln!("screenshot take_screenshot timed out");}
                }
                // match client.take_screenshot().await {
                //     Ok(b) => {
                //         qt_thread.queue(move |backend| {
                //             backend.screenshotCaptured(QByteArray::from(b.as_slice()))
                //         });
                //     }
                //     Err(e) => {
                //         qt_thread.queue(move |b| {
                //             b.initFailed(
                //                 QString::from(format!("Failed to take screenshot: {e}")),
                //                 QString::default(),
                //             )
                //         });
                //         return;
                //     }
                // }
                sleep_until(frame_started + FRAME_INTERVAL).await;
            }
            eprint!("screenshot service loop ended");
        }
        Err(e) => {
            eprintln!("screenshot client err: {e}");
            qt_thread.queue(move |b| {
                b.initFailed(
                    QString::from(format!("Failed to initialize screenshot client: {e}")),
                    QString::default(),
                )
            });
        }
    }
}

async fn run_capture_ios16_and_lower(
    qt_thread: QtThread<ScreenshotBackend>,
    provider: &dyn IdeviceProvider,
    capture_active: Arc<AtomicBool>,
) {
    match ScreenshotService::connect(provider).await {
        Ok(mut service) => {
            while capture_active.load(Ordering::Relaxed) {
                let frame_started = Instant::now();
                match service.take_screenshot().await {
                    Ok(b) => {
                        qt_thread.queue(move |backend| {
                            backend.screenshotCaptured(QByteArray::from(b.as_slice()))
                        });
                    }
                    Err(IdeviceError::ServiceNotFound) => {
                        debug!(
                            "ScreenshotR vanished or is unavailable, prompting developer image mount"
                        );
                        qt_thread.queue(move |b| {
                            b.initFailed(
                                QString::from("ScreenshotR service not found on device"),
                                QString::from("dev-img"),
                            )
                        });
                        return;
                    }
                    Err(e) => {
                        eprintln!("screenshotr take err: {e}");
                        qt_thread.queue(move |b| {
                            b.initFailed(
                                QString::from(format!("Failed to take screenshot: {e}")),
                                QString::default(),
                            )
                        });
                        return;
                    }
                }
                sleep_until(frame_started + FRAME_INTERVAL).await;
            }
            eprint!("screenshot service loop ended");
        }
        Err(IdeviceError::ServiceNotFound) => {
            debug!("Potentially no developer image mounted");
            qt_thread.queue(move |b| {
                b.initFailed(
                    QString::from("ScreenshotR service not found on device"),
                    QString::from("dev-img"),
                )
            });
        }
        Err(e) => {
            eprintln!("screenshotr connect failed: {e}");
            qt_thread.queue(move |b| {
                b.initFailed(
                    QString::from(format!("Failed to connect to ScreenshotR service: {e}")),
                    QString::default(),
                )
            });
        }
    }
}
