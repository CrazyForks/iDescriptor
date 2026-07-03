use crate::device_ctx;
use crate::query_sqlite::Query;
use crate::service_manager::ServiceManager;
use crate::springboard_services::SpringBoardServices;

use crate::utils::{empty_qjsvalue, engine_ptr_new_object, vend_app_documents};

use crate::{afc_services::AfcServices, run_sync};
use idevice::IdeviceService;
use idevice::afc::AfcClient;
use idevice::{provider::IdeviceProvider, springboardservices::SpringBoardServicesClient};
use qmetaobject::{QJSValue, prelude::*};
use std::ffi::c_void;
use std::sync::Arc;
use tokio::sync::Mutex;

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
    create_hause_arrest_afc_client:
        qt_method!(fn(&self, udid: QString, bundle_id: QString) -> QJSValue),
    create_service_manager: qt_method!(fn(&self, udid: QString, ios_version: u32) -> QJSValue),
    create_sqlite_query_backend: qt_method!(fn(&self, udid: QString, ios_version: u32) -> QJSValue),
    create_springboard_services_client: qt_method!(fn(&self, udid: QString) -> QJSValue),
}

impl ServiceFactory {
    pub fn new(engine_ptr: *mut c_void) -> Self {
        Self {
            base: Default::default(),
            engine_ptr,
            create_afc_client: Default::default(),
            create_hause_arrest_afc_client: Default::default(),
            create_service_manager: Default::default(),
            create_sqlite_query_backend: Default::default(),
            create_springboard_services_client: Default::default(),
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
                let maybe_device = device_ctx::get_device_opt(&udid_str).await;
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
            println!(
                "ServiceFactory: no AFC client available for {} (afc2={})",
                &udid_str, afc2
            );
            return empty_qjsvalue();
        };

        let obj = AfcServices::from_afc_client(afc, udid_str, None);
        let obj_ptr = qmetaobject::into_leaked_cpp_ptr(obj);

        engine_ptr_new_object(engine_ptr, obj_ptr)
    }

    fn create_hause_arrest_afc_client(&self, udid: QString, bundle_id: QString) -> QJSValue {
        let engine_ptr: *mut c_void = self.engine_ptr;
        let udid_clone = udid.clone();
        let bundle_id_clone = bundle_id.clone();
        if engine_ptr.is_null() {
            eprintln!("ServiceFactory: engine_ptr is null");
            return empty_qjsvalue();
        }

        let afc_res: anyhow::Result<AfcClient> = run_sync(async move {
            let device = device_ctx::get_device(udid).await?;

            let provider_guard = device.provider.lock().await;

            Ok(vend_app_documents(provider_guard.as_ref(), &bundle_id.to_string()).await?)
        });

        match afc_res {
            Ok(afc) => {
                let obj = AfcServices::from_afc_client(
                    Arc::new(Mutex::new(afc)),
                    udid_clone.to_string(),
                    Some(bundle_id_clone.to_string()),
                );
                let obj_ptr = qmetaobject::into_leaked_cpp_ptr(obj);

                engine_ptr_new_object(engine_ptr, obj_ptr)
            }
            Err(e) => {
                println!(
                    "Couldn't create hause_arrest_afc for bundle id {} for device {} : Error : {}",
                    bundle_id_clone,
                    udid_clone,
                    e.to_string()
                );

                return empty_qjsvalue();
            }
        }
    }

    fn create_service_manager(&self, udid: QString, ios_version: u32) -> QJSValue {
        let engine_ptr: *mut c_void = self.engine_ptr;
        if engine_ptr.is_null() {
            eprintln!("ServiceFactory: engine_ptr is null");
            return empty_qjsvalue();
        }
        let udid_clone = udid.to_string();
        let maybe_device = run_sync(async move { device_ctx::get_device_opt(udid).await });
        match maybe_device {
            Some(dev) => {
                let mng = ServiceManager::from_device(dev, udid_clone, ios_version);
                let obj_ptr = qmetaobject::into_leaked_cpp_ptr(mng);
                engine_ptr_new_object(engine_ptr, obj_ptr)
            }
            None => {
                println!("No device in create_service_manager");
                empty_qjsvalue()
            }
        }
    }

    fn create_sqlite_query_backend(&self, udid: QString, ios_version: u32) -> QJSValue {
        let engine_ptr: *mut c_void = self.engine_ptr;
        if engine_ptr.is_null() {
            eprintln!("ServiceFactory: engine_ptr is null");
            return empty_qjsvalue();
        }
        let mng = Query::with_device_attr(udid, ios_version);
        let obj_ptr = qmetaobject::into_leaked_cpp_ptr(mng);
        engine_ptr_new_object(engine_ptr, obj_ptr)
    }

    fn create_springboard_services_client(&self, udid: QString) -> QJSValue {
        let engine_ptr: *mut c_void = self.engine_ptr;
        if engine_ptr.is_null() {
            eprintln!("ServiceFactory: engine_ptr is null");
            return empty_qjsvalue();
        }
        let udid_clone = udid.to_string();
        let sp_res: anyhow::Result<SpringBoardServicesClient> = run_sync(async move {
            let device = device_ctx::get_device(udid).await?;
            let provider_guard = device.provider.lock().await;
            let provider_ref: &dyn IdeviceProvider = provider_guard.as_ref();
            Ok(SpringBoardServicesClient::connect(provider_ref).await?)
        });
        match sp_res {
            Ok(sp) => {
                let sp_wrapper = SpringBoardServices::new_with_sp_client(sp);
                let obj_ptr = qmetaobject::into_leaked_cpp_ptr(sp_wrapper);
                engine_ptr_new_object(engine_ptr, obj_ptr)
            }
            Err(err) => {
                println!(
                    "Failed to create SpringBoardServicesClient for device {}: {}",
                    udid_clone, err
                );
                empty_qjsvalue()
            }
        }
    }
}
