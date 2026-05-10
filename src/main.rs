#![recursion_limit = "4096"]
#![windows_subsystem = "windows"]

use cpp::*;
use idevice::{
    afc::AfcClient, diagnostics_relay::DiagnosticsRelayClient, lockdown::LockdownClient,
};
use qmetaobject::*;

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

use std::future::Future;
use std::sync::mpsc;
use tokio::runtime::Runtime;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;

use once_cell::sync::Lazy;

use crate::qquickimageprovider_imp::AddImageProvider;

pub mod afc_services;
pub mod apps;
pub mod core;
pub mod image_cache;
pub mod image_loader;
pub mod image_provider;
pub mod qquickimageprovider_imp;
pub mod qrc;
pub mod qt_threading;
pub mod query_sqlite;
pub mod service_factory;
pub mod service_manager;
pub mod utils;

pub const POSSIBLE_ROOT: &str = "../../../../";
pub const APP_LABEL: &str = "iDescriptor";
pub const EV_CONNECTED: u32 = 1;
pub const EV_DISCONNECTED: u32 = 2;
pub const EV_PAIRING_PENDING: u32 = 3;
pub const EV_FAIL: u32 = 4;

// TODO
// #[global_allocator]
// static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

cpp! {{
    #include <QQuickStyle>
    #include <QQuickWindow>
    #include <QQmlContext>
    #include <QLoggingCategory>
    #include <QtGui/QGuiApplication>
    #include <QIcon>

    #include "src/live_reload.cpp"
}}

#[derive(Clone)]
pub struct DeviceServices {
    pub afc: Arc<Mutex<AfcClient>>,
    pub afc2: Option<Arc<Mutex<AfcClient>>>,
    pub diag: Arc<Mutex<DiagnosticsRelayClient>>,
    pub heartbeat_task: Option<Arc<JoinHandle<()>>>,
    pub video_streams: Arc<Mutex<HashMap<String, oneshot::Sender<()>>>>,
    pub provider: Arc<Mutex<Box<dyn idevice::provider::IdeviceProvider>>>,
    pub lockdown: Arc<Mutex<LockdownClient>>,
}

pub static APP_DEVICE_STATE: Lazy<Mutex<HashMap<String, DeviceServices>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

static RUNTIME: Lazy<Runtime> = Lazy::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap()
});

pub fn run_sync<F, R>(fut: F) -> R
where
    F: Future<Output = R> + Send + 'static,
    R: Send + 'static,
{
    let (tx, rx) = mpsc::sync_channel(1);

    RUNTIME.spawn(async move {
        let res = fut.await;
        let _ = tx.send(res);
    });

    rx.recv().expect("Tokio runtime worker panicked")
}

fn main() {
    let ui_live_reload = true;
    // #[cfg(target_os = "windows")]
    // unsafe {
    //     use windows::Win32::System::Console::*;
    //     if AttachConsole(ATTACH_PARENT_PROCESS).is_err() && cli::will_run_in_console() {
    //         let _ = AllocConsole();
    //     }
    // }

    // let _ = util::install_crash_handler();
    // utils::init_logging();
    // qmetaobject::log::init_qt_to_rust();

    cpp!(unsafe [] {

        #define FLUENTUI_BUILD_STATIC_LIB 1

        #ifdef WIN32
            // ::SetUnhandledExceptionFilter(MyUnhandledExceptionFilter);
            qputenv("QT_QPA_PLATFORM", "windows:darkmode=2");
        #endif
        #if (QT_VERSION >= QT_VERSION_CHECK(6, 0, 0))
            qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
        #else
            qputenv("QT_QUICK_CONTROLS_STYLE", "Default");
        #endif
        #ifdef Q_OS_LINUX
            // fix bug UOSv20 v-sync does not work
            qputenv("QSG_RENDER_LOOP", "basic");
        #endif

        // FIXME: fluentui example app was forcing OpenGL
        // but do we need this ?
        // #if (QT_VERSION >= QT_VERSION_CHECK(6, 0, 0))
        //     QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
        // #endif
        #if (QT_VERSION < QT_VERSION_CHECK(6, 0, 0))
            QApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
            QApplication::setAttribute(Qt::AA_UseHighDpiPixmaps);
        #if (QT_VERSION >= QT_VERSION_CHECK(5, 14, 0))
            QApplication::setHighDpiScaleFactorRoundingPolicy(
                Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);
        #endif
        #endif
            QCoreApplication::setOrganizationName("iDescriptor");
            QCoreApplication::setApplicationName("iDescriptor");

            // FIXME
            // QCoreApplication::setApplicationVersion(VERSION);
            // FIXME
            // if (a.arguments().contains("--reset-settings")) {
            //     // SettingsManager::sharedInstance()->clear();
            //     QMessageBox::information(nullptr, "Settings Reset",
            //                             "All application settings have been reset to "
            //                             "their default values.");
            // }
            // QQmlApplicationEngine engine;

        #ifdef WIN32
            QString appPath = QCoreApplication::applicationDirPath();
            QString gstPluginPath =
                QDir::toNativeSeparators(appPath + "/gstreamer-1.0");
            QString gstPluginScannerPath = QDir::toNativeSeparators(
                appPath + "/gstreamer-1.0/libexec/gst-plugin-scanner.exe");

            const char *oldPath = getenv("PATH");
            QString newPath = appPath + ";" + QString(oldPath);
            qputenv("PATH", newPath.toUtf8());

            qputenv("GST_PLUGIN_PATH", gstPluginPath.toUtf8());
            qDebug() << "GST_PLUGIN_PATH=" << gstPluginPath;
            qputenv("GST_REGISTRY_REUSE_PLUGIN_SCANNER", "no");
            qDebug() << "GST_REGISTRY_REUSE_PLUGIN_SCANNER=no";
            qputenv("GST_PLUGIN_SYSTEM_PATH", gstPluginPath.toUtf8());
            qDebug() << "GST_PLUGIN_SYSTEM_PATH=" << gstPluginPath;
            qputenv("GST_DEBUG", "GST_PLUGIN_LOADING:5");
            qDebug() << "GST_DEBUG=GST_PLUGIN_LOADING:5";
            qputenv("GST_PLUGIN_SCANNER_1_0", gstPluginScannerPath.toUtf8());
            qDebug() << "GST_PLUGIN_SCANNER_1_0=" << gstPluginScannerPath;
        #endif
        #ifdef __APPLE__
            QString appPath = QCoreApplication::applicationDirPath();
            QString frameworksPath =
                QDir::toNativeSeparators(appPath + "/../Frameworks");
            QString gstPluginPath =
                QDir::toNativeSeparators(frameworksPath + "/gstreamer");
            QString gstPluginScannerPath =
                QDir::toNativeSeparators(frameworksPath + "/gst-plugin-scanner");

            setenv("GST_PLUGIN_PATH", gstPluginPath.toUtf8().constData(), 1);
            setenv("GST_PLUGIN_SYSTEM_PATH", gstPluginPath.toUtf8().constData(), 1);
            setenv("GST_PLUGIN_SCANNER", gstPluginScannerPath.toUtf8().constData(), 1);
        #endif
    });

    if cfg!(compiled_qml) {
        // For some reason on some devices QML detects that debugger is connected and fails to load pre-compiled qml files
        cpp!(unsafe [] { qputenv("QML_FORCE_DISK_CACHE", "1"); });
    }

    crate::qrc::rsrc();
    // #[cfg(not(compiled_qml))]
    // crate::resources_qml::rsrc_qml();

    qml_register_type::<core::Core>(cstr::cstr!("iDescriptor"), 1, 0, cstr::cstr!("Core"));
    qml_register_type::<query_sqlite::Query>(
        cstr::cstr!("iDescriptor"),
        1,
        0,
        cstr::cstr!("Query"),
    );

    let mut engine = QmlEngine::new();
    // let mut dpi = cpp!(unsafe[] -> f64 as "double" { return QGuiApplication::primaryScreen()->logicalDotsPerInch() / 96.0; });

    let obj = QObjectBox::new(image_loader::ImageLoader::default());
    engine.set_object_property("imageLoader".into(), obj.pinned());

    let apps_impl = QObjectBox::new(apps::Apps::new_with_state());
    engine.set_object_property("apps".into(), apps_impl.pinned());

    let provider_ref_cell = QObjectBox::new(image_provider::ImageProvider::default(obj));
    engine.add_image_provider("thumb", provider_ref_cell);

    let engine_ptr = engine.cpp_ptr();

    let service_factory = QObjectBox::new(crate::service_factory::ServiceFactory::new(engine_ptr));
    engine.set_object_property("serviceFactory".into(), service_factory.pinned());

    if !ui_live_reload {
        use std::path::PathBuf;
        // Try to load from disk first
        let path = (|| -> Option<String> {
            let path = if cfg!(any(target_os = "macos", target_os = "ios")) {
                PathBuf::from("../Resources/ui/Main.qml")
            } else {
                PathBuf::from("./ui/Main.qml")
            };
            let final_path = std::env::current_exe().ok()?.parent()?.join(path);
            if final_path.exists() {
                Some(String::from(final_path.to_str()?))
            } else {
                None
            }
        })();
        if let Some(path) = path {
            engine.load_file(path.into());
        } else {
            // Load from resources
            engine.load_url(QString::from("qrc:/src/ui/Main.qml").into());
        }
    } else {
        engine.load_file(format!("{}/src/ui/Main.qml", env!("CARGO_MANIFEST_DIR")).into());
        let ui_path = QString::from(format!("{}/src/ui", env!("CARGO_MANIFEST_DIR")));
        cpp!(unsafe [engine_ptr as "QQmlApplicationEngine *", ui_path as "QString"] { init_live_reload(engine_ptr, ui_path); });
    }

    engine.exec();
}
