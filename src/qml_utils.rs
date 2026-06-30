use cpp::cpp;
use log::debug;
use qmetaobject::{QJSValue, prelude::*};
use std::ffi::c_void;

cpp! {{
    #include <QCoreApplication>
    #include <QGuiApplication>
    #include <QQmlEngine>
    #include <QString>
    #include <QTranslator>
}}

#[derive(QObject, Default)]
pub struct QmlUtils {
    base: qt_base_class!(trait QObject),
    engine_ptr: Option<*mut c_void>,
    get_lockdown_dir: qt_method!(fn(&self) -> QString),
    generate_uuid: qt_method!(fn(&self) -> QString),
    set_language: qt_method!(fn(&self, lang_id: QString) -> bool),
    language_changed: qt_signal!(),
    setup_tool_window: qt_method!(fn(&self, win: QJSValue)),
    setup_main_window: qt_method!(fn(&self, win: QJSValue)),
}

impl QmlUtils {
    pub fn new(engine_ptr: *mut c_void) -> Self {
        Self {
            engine_ptr: Some(engine_ptr),
            ..Default::default()
        }
    }

    pub fn apply_language_to_engine(engine_ptr: *mut c_void, lang_id: QString) -> bool {
        if engine_ptr.is_null() {
            eprintln!("QmlUtils: engine_ptr is null, cannot apply language");
            return false;
        }

        cpp!(unsafe [engine_ptr as "QQmlEngine *", lang_id as "QString"] -> bool as "bool" {
            static QTranslator translator;

            QString normalized = lang_id.trimmed().toLower();
            if (normalized.isEmpty() || normalized == QStringLiteral("english")) {
                normalized = QStringLiteral("en");
            } else if (normalized == QStringLiteral("german")) {
                normalized = QStringLiteral("de");
            }

            QCoreApplication::removeTranslator(&translator);

            if (normalized != QStringLiteral("en")) {
                if (!translator.load(QStringLiteral(":/translations/") + normalized + QStringLiteral(".qm"))) {
                    engine_ptr->retranslate();
                    return false;
                }

                qApp->setLayoutDirection(
                    (normalized == QStringLiteral("ar")
                        || normalized == QStringLiteral("fa")
                        || normalized == QStringLiteral("he"))
                        ? Qt::RightToLeft
                        : Qt::LeftToRight
                );
                QCoreApplication::installTranslator(&translator);
            } else {
                qApp->setLayoutDirection(Qt::LeftToRight);
            }

            engine_ptr->retranslate();
            return true;
        })
    }

    fn get_lockdown_dir(&self) -> QString {
        QString::from(crate::utils::get_lockdown_path().to_str().unwrap())
    }

    fn generate_uuid(&self) -> QString {
        QString::from(uuid::Uuid::new_v4().to_string())
    }

    fn set_language(&self, lang_id: QString) -> bool {
        if self.engine_ptr.is_none() {
            debug!("QmlUtils: engine_ptr is none, cannot set_language");
            return false;
        };
        let applied = Self::apply_language_to_engine(self.engine_ptr.unwrap(), lang_id);
        self.language_changed();
        applied
    }

    fn setup_tool_window(&self, win: QJSValue) {
        let win_id = crate::utils::get_window_id(win);

        crate::platform::macos::apply_tool_frame(win_id);
    }

    fn setup_main_window(&self, win: QJSValue) {
        let win_id = crate::utils::get_window_id(win);

        crate::platform::macos::apply_main_window(win_id);
    }
}
