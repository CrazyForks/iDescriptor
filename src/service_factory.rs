use crate::utils::{empty_qjsvalue, engine_ptr_new_object};
use crate::{APP_DEVICE_STATE, afc_services::AfcServices, run_sync};
use qmetaobject::{QJSValue, prelude::*};
use std::ffi::c_void;

/*
    we need this because qml side
    cannot pass constructor args
    https://forum.qt.io/topic/155986/qt6-qabstractlistmodel-constructor-with-two-arguments-qml-element-is-not-creatable/2
*/
#[derive(QObject)]
pub struct ServiceFactory {
    base: qt_base_class!(trait QObject),
    /* SAFETY: check if engine_ptr.is_null() */
    engine_ptr: *mut c_void,
    create_afc_client: qt_method!(fn(&self, udid: QString, afc2: bool) -> QJSValue),
}

impl ServiceFactory {
    pub fn new(engine_ptr: *mut c_void) -> Self {
        Self {
            base: Default::default(),
            engine_ptr,
            create_afc_client: Default::default(),
        }
    }

    fn create_afc_client(&self, udid: QString, afc2: bool) -> QJSValue {
        let udid_str = udid.to_string();
        let engine_ptr: *mut c_void = self.engine_ptr;

        if engine_ptr.is_null() {
            eprintln!("ServiceFactory: engine_ptr is null");
            return empty_qjsvalue();
        }

        let afc_arc = run_sync({
            let udid_str = udid_str.clone();
            async move {
                let maybe_device = APP_DEVICE_STATE
                    .lock()
                    .await
                    .get(udid_str.as_str())
                    .cloned();
                let device = match maybe_device {
                    Some(d) => d,
                    None => {
                        eprintln!("ServiceFactory: device with UDID {udid_str} not found");
                        return None;
                    }
                };

                if afc2 {
                    device.afc2.clone().or(None)
                } else {
                    Some(device.afc.clone())
                }
            }
        });

        let Some(afc) = afc_arc else {
            eprintln!("ServiceFactory: no AFC client available for {udid_str} (afc2={afc2})");
            return empty_qjsvalue();
        };

        let obj = AfcServices::from_afc_client(afc, udid_str);
        let obj_ptr = qmetaobject::into_leaked_cpp_ptr(obj);

        engine_ptr_new_object(engine_ptr, obj_ptr)
    }
}
