#![recursion_limit = "4096"]
// TODO: disable on release build
// #![windows_subsystem = "windows"]
// #![windows_subsystem = "windows"]

use cpp::*;
use idevice::{
    afc::AfcClient, diagnostics_relay::DiagnosticsRelayClient, lockdown::LockdownClient,
};
use qmetaobject::*;
use simplelog::{ColorChoice, ConfigBuilder, LevelFilter, TermLogger, TerminalMode};

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
pub mod airplay;
pub mod apps;
pub mod backup_manager;
pub mod constants;
pub mod core;
pub mod dev_imgs;
pub mod dev_imgs_manager;
pub mod device_ctx;
pub mod device_db;
#[cfg(not(target_os = "macos"))]
pub mod diagnose;
pub mod gallery;
pub mod gallery_fs_provider;
pub mod gallery_sqlite_provider;
#[cfg(not(target_os = "macos"))]
pub mod ifuse;
pub mod image_cache;
pub mod image_loader;
pub mod image_provider;
pub mod io_manager;
pub mod jailbroken;
pub mod list_model;
pub mod media_streamer;
pub mod platform;
pub mod qml_image;
pub mod qml_utils;
pub mod qquickimageprovider_imp;
pub mod qrc;
pub mod qt_threading;
pub mod screenshot;
pub mod service_factory;
pub mod service_manager;
pub mod settings_manager;
pub mod springboard_services;
pub mod status_window_controller;
pub mod transfer_speed_tester;
pub mod ui_qrc;
pub mod updater;
pub mod utils;
pub mod web_wireless_gallery_import;

// FIXME: branch
pub const IMAGE_LIST_URL: &str = "https://raw.githubusercontent.com/iDescriptor/iDescriptor/refs/heads/qmeta-qml/DeveloperDiskImages.json";
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
    #include <QFont>
    #include <QQmlFileSelector>
    #include <QIcon>

    #include "src/live_reload.cpp"
    #include "src/native/networkdeviceprovider.h"
}}

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
    TermLogger::init(
        LevelFilter::Debug,
        ConfigBuilder::new().build(),
        TerminalMode::Mixed,
        ColorChoice::Auto,
    )
    .expect("Failed to initialize logger");

    let ui_live_reload = utils::env_flag("IDESCRIPTOR_UI_LIVE_RELOAD");
    let qml_from_fs = ui_live_reload || utils::env_flag("IDESCRIPTOR_QML_FROM_FS");

    // let _ = util::install_crash_handler();
    qmetaobject::log::init_qt_to_rust();
    let icons_path = if ui_live_reload {
        QString::from(format!("{}/resources/icons/", env!("CARGO_MANIFEST_DIR")))
    } else {
        QString::from(":/resources/icons/")
    };

    cpp!(unsafe [icons_path as "QString"] {

        #define FLUENTUI_BUILD_STATIC_LIB 1
        #ifdef WIN32
            // ::SetUnhandledExceptionFilter(MyUnhandledExceptionFilter);
            qputenv("QT_QPA_PLATFORM", "windows:darkmode=2");
        #endif
        // #if (QT_VERSION >= QT_VERSION_CHECK(6, 0, 0))
        //     qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
        // #else
        //     qputenv("QT_QUICK_CONTROLS_STYLE", "Default");
        // #endif
        // #ifdef Q_OS_LINUX
        //     // fix bug UOSv20 v-sync does not work
        //     qputenv("QSG_RENDER_LOOP", "basic");
        // #endif

        #ifdef Q_OS_WINDOWS
            QQuickStyle::setStyle("FluentWinUI3");
        #endif
        #ifndef Q_OS_LINUX
            // uxplay now uses qml6glsink so we have to use opengl
            // Linux is fine with QT_QPA_PLATFORM=xcb
            QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
        #endif

        // QCoreApplication::setAttribute(Qt::AA_UseOpenGLES);
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
        // #ifdef __APPLE__
        //     QString appPath = QCoreApplication::applicationDirPath();
        //     QString frameworksPath =
        //         QDir::toNativeSeparators(appPath + "/../Frameworks");
        //     QString gstPluginPath =
        //         QDir::toNativeSeparators(frameworksPath + "/gstreamer");
        //     QString gstPluginScannerPath =
        //         QDir::toNativeSeparators(frameworksPath + "/gst-plugin-scanner");

        //     setenv("GST_PLUGIN_PATH", gstPluginPath.toUtf8().constData(), 1);
        //     setenv("GST_PLUGIN_SYSTEM_PATH", gstPluginPath.toUtf8().constData(), 1);
        //     setenv("GST_PLUGIN_SCANNER", gstPluginScannerPath.toUtf8().constData(), 1);
        // #endif
    });

    crate::qrc::rsrc();
    crate::ui_qrc::qml();

    #[cfg(target_os = "macos")]
    {
        crate::qrc::macos_rsrc();
        crate::ui_qrc::macos_qml();
    }

    // workaround for gstreamer plugins not being loaded on Windows
    #[cfg(target_os = "windows")]
    {
        // in the release build we bundle gstreamer plugins
        if !cfg!(debug_assertions) {
            // unsafe is needed because of env::set_var
            unsafe {
                use std::env;

                let exe_dir = std::env::current_exe()
                    .unwrap()
                    .parent()
                    .unwrap()
                    .to_path_buf();

                let gst_plugin_path = exe_dir.join("gstreamer-1.0");

                env::set_var(
                    "GST_PLUGIN_PATH",
                    gst_plugin_path.to_string_lossy().to_string(),
                );
            }
        }

        crate::qrc::windows_rsrc();
        crate::ui_qrc::windows_qml();
    }

    // qml_register_type::<gallery::Query>(cstr::cstr!("iDescriptor"), 1, 0, cstr::cstr!("Query"));
    qml_register_type::<screenshot::ScreenshotBackend>(
        cstr::cstr!("iDescriptor"),
        1,
        0,
        cstr::cstr!("ScreenshotBackend"),
    );
    qml_register_type::<qml_image::QmlImage>(
        cstr::cstr!("iDescriptor"),
        1,
        0,
        cstr::cstr!("QmlImage"),
    );
    // FIXME: should be singleton
    qml_register_type::<jailbroken::Jailbroken>(
        cstr::cstr!("iDescriptor"),
        1,
        0,
        cstr::cstr!("JailbrokenImp"),
    );

    let mut engine = QmlEngine::new();
    let engine_ptr = engine.cpp_ptr();

    #[cfg(target_os = "windows")]
    cpp!(unsafe [] {
        QGuiApplication::setFont(QFont("Segoe UI"));
    });

    let settings_manager_impl = settings_manager::SettingsManager::default();
    let initial_language = settings_manager_impl.language();
    qml_utils::QmlUtils::apply_language_to_engine(engine_ptr, initial_language);
    let settings_manager = QObjectBox::new(settings_manager_impl);
    engine.set_object_property("settingsManager".into(), settings_manager.pinned());

    let updater = QObjectBox::new(updater::Updater::new_with_state());
    engine.set_object_property("UpdaterImp".into(), updater.pinned());

    let core_obj = QObjectBox::new(core::Core::default());
    engine.set_object_property("core".into(), core_obj.pinned());

    let obj = QObjectBox::new(image_loader::ImageLoader::default());
    engine.set_object_property("imageLoader".into(), obj.pinned());

    let apps_impl = QObjectBox::new(apps::Apps::new_with_state());
    engine.set_object_property("apps".into(), apps_impl.pinned());

    let provider_ref_cell = QObjectBox::new(image_provider::ImageProvider::default(obj));
    engine.add_image_provider("thumb", provider_ref_cell);

    let io_manager = QObjectBox::new(io_manager::IOManager::default());
    engine.set_object_property("ioManager".into(), io_manager.pinned());

    let airplay = QObjectBox::new(airplay::Airplay::default());
    engine.set_object_property("AirplayImp".into(), airplay.pinned());

    let dev_imgs_manager = QObjectBox::new(dev_imgs_manager::DevImgsManager::default());
    engine.set_object_property("DevImgsManager".into(), dev_imgs_manager.pinned());

    let wireless_import =
        QObjectBox::new(web_wireless_gallery_import::WebWirelessGalleryImport::new_with_state());
    engine.set_object_property("WebWirelessGalleryImport".into(), wireless_import.pinned());

    let backup_manager = QObjectBox::new(backup_manager::BackupManager::new_with_state());
    engine.set_object_property("backupManager".into(), backup_manager.pinned());

    #[cfg(not(target_os = "macos"))]
    let ifuse = QObjectBox::new(ifuse::IFuse::new_with_state());
    #[cfg(not(target_os = "macos"))]
    engine.set_object_property("iFuse".into(), ifuse.pinned());
    #[cfg(not(target_os = "macos"))]
    let diagnose = QObjectBox::new(diagnose::Diagnose::new_with_state());
    #[cfg(not(target_os = "macos"))]
    engine.set_object_property("DiagnoseImpl".into(), diagnose.pinned());

    let qml_utils = QObjectBox::new(qml_utils::QmlUtils::new(engine_ptr));
    engine.set_object_property("QmlUtils".into(), qml_utils.pinned());

    let status_window_controller =
        QObjectBox::new(status_window_controller::StatusWindowController::default());
    engine.set_object_property(
        "StatusWindowController".into(),
        status_window_controller.pinned(),
    );

    cpp!(unsafe [engine_ptr as "QQmlApplicationEngine *"] {

        static QQmlFileSelector* s_fileSelector = nullptr;
        if (!s_fileSelector) {
            s_fileSelector = new QQmlFileSelector(engine_ptr, engine_ptr);
        }


        static NetworkDeviceProvider* s_networkProvider = nullptr;
        if (!s_networkProvider) {
            s_networkProvider = new NetworkDeviceProvider(QCoreApplication::instance());
            engine_ptr->rootContext()->setContextProperty("NetworkDeviceProvider", s_networkProvider);

        }
        // #endif
        // engine_ptr->rootContext()->setContextProperty("NetworkDeviceProvider", NetworkDeviceProvider::sharedInstance());
    });

    // FIXME: workaround to find FluentUI
    // in dev builds
    #[cfg(debug_assertions)]
    cpp!(unsafe [engine_ptr as "QQmlApplicationEngine *"] {
        #ifdef Q_OS_WINDOWS
            engine_ptr->addImportPath("C:/Qt/6.9.3/mingw_64/qml");
        #endif
    });

    let service_factory = QObjectBox::new(crate::service_factory::ServiceFactory::new(engine_ptr));
    engine.set_object_property("serviceFactory".into(), service_factory.pinned());

    let windows_qml_entry = "src/ui/platform/windows/Main.qml";
    let macos_qml_entry = "src/ui/platform/macos/Main.qml";
    let other_qml_entry = "src/ui/Main.qml";

    let entry = if cfg!(target_os = "windows") {
        windows_qml_entry
    } else if cfg!(target_os = "macos") {
        macos_qml_entry
    } else {
        other_qml_entry
    };

    if ui_live_reload {
        let ui_path = QString::from(utils::source_qml_path("src/ui"));
        let entry_path = QString::from(utils::source_qml_path(entry));

        eprintln!("QML live reload enabled: {}", entry_path.to_string());
        engine.load_file(entry_path.clone().into());

        cpp!(unsafe [
            engine_ptr as "QQmlApplicationEngine *",
            ui_path as "QString",
            entry_path as "QString"
        ] {
            init_live_reload(engine_ptr, ui_path, entry_path);
        });
    } else if qml_from_fs {
        let path = utils::deployed_qml_path(entry).unwrap_or_else(|| utils::source_qml_path(entry));
        eprintln!("Loading QML from filesystem: {path}");
        engine.load_file(path.into());
    } else if let Some(path) = utils::deployed_qml_path(entry) {
        eprintln!("Loading deployed QML from filesystem: {path}");
        engine.load_file(path.into());
    } else {
        eprintln!("Loading QML from resources: qrc:/{entry}");
        engine.load_url(QString::from(format!("qrc:/{}", entry)).into());
    }

    // cpp!(unsafe [engine_ptr as "QQmlApplicationEngine *"] {

    // });

    engine.exec();
}
