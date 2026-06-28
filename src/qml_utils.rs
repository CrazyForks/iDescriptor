use qmetaobject::{QJSValue, prelude::*};

#[derive(QObject, Default)]
pub struct QmlUtils {
    base: qt_base_class!(trait QObject),
    get_lockdown_dir: qt_method!(fn(&self) -> QString),
    generate_uuid: qt_method!(fn(&self) -> QString),
    // FIXME: implement
    // setup_tool_window: qt_method!(fn(&self, win_id: u64)),
    // setup_main_window: qt_method!(fn(&self, win: QJSValue)),
}

impl QmlUtils {
    fn get_lockdown_dir(&self) -> QString {
        QString::from(crate::utils::get_lockdown_path().to_str().unwrap())
    }

    fn generate_uuid(&self) -> QString {
        QString::from(uuid::Uuid::new_v4().to_string())
    }

    // fn setup_tool_window(&self, win_id: u64) {
    //     crate::platform::mac::apply_tool_frame(win_id);
    // }

    // fn setup_main_window(&self, win: QJSValue) {
    //     let win_id = crate::utils::get_window_id(win);

    //     crate::platform::mac::apply_main_window(win_id);
    // }
}
