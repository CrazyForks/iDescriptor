// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

use crate::gallery::Query;
use crate::service_manager::ServiceManager;
use crate::springboard_services::SpringBoardServices;
use crate::transfer_speed_tester::TransferSpeedTester;
use crate::{RUNTIME, device_ctx};

use crate::utils::{empty_qjsvalue, engine_ptr_new_object, vend_app_documents};

use crate::{afc_services::AfcServices, qt_threading::QtThreading, run_sync};
use idevice::IdeviceService;
use idevice::afc::AfcClient;
use idevice::{provider::IdeviceProvider, springboardservices::SpringBoardServicesClient};
use macros::QtThreading;
use qmetaobject::{QJSValue, prelude::*};
use std::ffi::c_void;
use std::sync::Arc;
use tokio::sync::Mutex;

/*
    we need this because qml side
    cannot pass constructor args
    https://forum.qt.io/topic/155986/qt6-qabstractlistmodel-constructor-with-two-arguments-qml-element-is-not-creatable/2
*/
#[allow(non_snake_case)]
#[derive(QObject, Default, QtThreading)]
pub struct ServiceFactory {
    base: qt_base_class!(trait QObject),
    /* SAFETY: check if engine_ptr.is_null() */
    engine_ptr: Option<*mut c_void>,
    create_afc_client:
        qt_method!(fn(&self, udid: QString, connection_id: u64, afc2: bool) -> QJSValue),
    create_hause_arrest_afc_client:
        qt_method!(fn(&self, udid: QString, connection_id: u64, bundle_id: QString)),
    create_service_manager:
        qt_method!(fn(&self, udid: QString, connection_id: u64, ios_version: u32) -> QJSValue),
    create_query_backend:
        qt_method!(fn(&self, udid: QString, connection_id: u64, ios_version: u32) -> QJSValue),
    create_springboard_services_client:
        qt_method!(fn(&self, udid: QString, connection_id: u64) -> QJSValue),
    create_transfer_speed_tester:
        qt_method!(fn(&self, udid: QString, connection_id: u64) -> QJSValue),

    houseArrestAfcClientCreated: qt_signal!(client: QJSValue, udid: QString, connection_id: u64, bundle_id: QString),
}

impl ServiceFactory {
    pub fn new(engine_ptr: *mut c_void) -> Self {
        Self {
            engine_ptr: Some(engine_ptr),
            ..Default::default()
        }
    }

    fn create_afc_client(&self, udid: QString, connection_id: u64, afc2: bool) -> QJSValue {
        let udid_str = udid.to_string();
        let engine_ptr: *mut c_void = self.engine_ptr.unwrap_or(std::ptr::null_mut());

        if engine_ptr.is_null() {
            eprintln!("ServiceFactory: engine_ptr is null");
            return empty_qjsvalue();
        }

        let afc_arc = run_sync({
            let udid_str = udid_str.clone();
            async move {
                let maybe_device =
                    device_ctx::get_device_for_connection_opt(&udid_str, connection_id).await;
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

    fn create_hause_arrest_afc_client(
        &self,
        udid: QString,
        connection_id: u64,
        bundle_id: QString,
    ) {
        if self.engine_ptr.is_none_or(|ptr| ptr.is_null()) {
            eprintln!("ServiceFactory: engine_ptr is null");
            return;
        }

        let qt_thread = self.qt_thread();

        RUNTIME.spawn(async move {
            let afc_result: anyhow::Result<AfcClient> = async {
                let device = device_ctx::get_device_for_connection_opt(udid.clone(), connection_id)
                    .await
                    .ok_or_else(|| anyhow::anyhow!("device connection is no longer current"))?;
                let provider = device.provider.lock().await;

                Ok(vend_app_documents(provider.as_ref(), &bundle_id.to_string()).await?)
            }
            .await;

            qt_thread.queue(move |factory| match afc_result {
                Ok(afc) => {
                    let Some(engine_ptr) = factory.engine_ptr else {
                        factory.houseArrestAfcClientCreated(
                            empty_qjsvalue(),
                            udid,
                            connection_id,
                            bundle_id,
                        );
                        return;
                    };

                    if engine_ptr.is_null() {
                        factory.houseArrestAfcClientCreated(
                            empty_qjsvalue(),
                            udid,
                            connection_id,
                            bundle_id,
                        );
                        return;
                    }

                    let object = AfcServices::from_afc_client(
                        Arc::new(Mutex::new(afc)),
                        udid.to_string(),
                        Some(bundle_id.to_string()),
                    );

                    let object_ptr = qmetaobject::into_leaked_cpp_ptr(object);

                    let client = engine_ptr_new_object(engine_ptr, object_ptr);

                    factory.houseArrestAfcClientCreated(client, udid, connection_id, bundle_id);
                }
                Err(error) => {
                    log::warn!(
                        "Couldn't create house-arrest AFC for bundle {} on device {}: {}",
                        bundle_id,
                        udid,
                        error
                    );

                    factory.houseArrestAfcClientCreated(
                        empty_qjsvalue(),
                        udid,
                        connection_id,
                        bundle_id,
                    );
                }
            });
        });
    }

    fn create_service_manager(
        &self,
        udid: QString,
        connection_id: u64,
        ios_version: u32,
    ) -> QJSValue {
        let engine_ptr: *mut c_void = self.engine_ptr.unwrap_or(std::ptr::null_mut());
        if engine_ptr.is_null() {
            eprintln!("ServiceFactory: engine_ptr is null");
            return empty_qjsvalue();
        }
        let udid_clone = udid.to_string();
        let maybe_device = run_sync(async move {
            device_ctx::get_device_for_connection_opt(udid, connection_id).await
        });
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

    fn create_query_backend(
        &self,
        udid: QString,
        connection_id: u64,
        ios_version: u32,
    ) -> QJSValue {
        let engine_ptr: *mut c_void = self.engine_ptr.unwrap_or(std::ptr::null_mut());
        if engine_ptr.is_null() {
            eprintln!("ServiceFactory: engine_ptr is null");
            return empty_qjsvalue();
        }
        let mng = Query::with_device_attr(udid, connection_id, ios_version);
        let obj_ptr = qmetaobject::into_leaked_cpp_ptr(mng);
        engine_ptr_new_object(engine_ptr, obj_ptr)
    }

    fn create_springboard_services_client(&self, udid: QString, connection_id: u64) -> QJSValue {
        let engine_ptr: *mut c_void = self.engine_ptr.unwrap_or(std::ptr::null_mut());
        if engine_ptr.is_null() {
            eprintln!("ServiceFactory: engine_ptr is null");
            return empty_qjsvalue();
        }
        let udid_clone = udid.to_string();
        let sp_res: anyhow::Result<SpringBoardServicesClient> = run_sync(async move {
            let device = device_ctx::get_device_for_connection_opt(udid, connection_id)
                .await
                .ok_or_else(|| anyhow::anyhow!("device connection is no longer current"))?;
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

    fn create_transfer_speed_tester(&self, udid: QString, connection_id: u64) -> QJSValue {
        let engine_ptr: *mut c_void = self.engine_ptr.unwrap_or(std::ptr::null_mut());
        if engine_ptr.is_null() {
            log::error!("ServiceFactory: engine_ptr is null while creating transfer speed tester");
            return empty_qjsvalue();
        }

        let udid = udid.to_string();
        let device = run_sync({
            let udid = udid.clone();
            async move { device_ctx::get_device_for_connection_opt(udid, connection_id).await }
        });
        let Some(device) = device else {
            log::warn!("ServiceFactory: device {udid} not found for transfer speed tester");
            return empty_qjsvalue();
        };

        let tester = TransferSpeedTester::new(device.afc, udid);
        let obj_ptr = qmetaobject::into_leaked_cpp_ptr(tester);
        engine_ptr_new_object(engine_ptr, obj_ptr)
    }
}
