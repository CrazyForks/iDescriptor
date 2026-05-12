use qmetaobject::prelude::*;
use qttypes::{QVariantMap,QStringList};
use crate::device_ctx::{DeviceServices,get_device_opt};
use crate::{RUNTIME, run_sync, utils,qt_threading::{QtThread,QtThreading}};
use macros::QtThreading;
use idevice::{afc::opcode::AfcFopenMode, provider};
use idevice::services::core_device_proxy::CoreDeviceProxy;
use idevice::{
    IdeviceService, RsdService, amfi,
    dvt::{location_simulation::LocationSimulationClient, remote_server::RemoteServerClient},
    installation_proxy::InstallationProxyClient,
    mobile_image_mounter::ImageMounter,
    provider::IdeviceProvider,
    rsd::RsdHandshake,
    simulate_location::LocationSimulationService,
    springboardservices::SpringBoardServicesClient,
};
use plist::Value;

use plist_macro::plist;
use serde_json;
use std::{io::Read, pin::Pin, time::Duration};

#[derive(Default, QObject, QtThreading)]
pub struct ServiceManager {
    base: qt_base_class!(trait QObject),

    get_cable_info: qt_method!(fn(&self)),
    reveal_developer_mode_option_in_ui: qt_method!(fn(&self)),
    query_mobilegestalt: qt_method!(fn(&self, keys: QStringList)),
    mount_dev_image: qt_method!(fn(&self, image_path: QString, sig: QString)),
    get_mounted_image: qt_method!(fn(&self)),
    fetch_installed_apps: qt_method!(fn(&self)),
    set_location: qt_method!(fn(&self, latitude: QString, longitude: QString) -> i32),
    fetch_app_icon: qt_method!(fn(&self, bundle_id: QString)),
    fetch_disk_usage: qt_method!(fn(&self)),
    restart: qt_method!(fn(&self) -> bool),
    shutdown: qt_method!(fn(&self) -> bool),
    enter_recovery_mode: qt_method!(fn(&self) -> bool),
    install_ipa: qt_method!(fn(&self, ipa_path: QString)),
    enable_wifi_connections: qt_method!(fn(&self)),

    // Signals
    cable_info_retrieved: qt_signal!(info: QString),
    mobilegestalt_info_retrieved: qt_signal!(info: QVariantMap),
    dev_image_mounted: qt_signal!(success: bool, is_locked: bool),
    developer_mode_option_revealed: qt_signal!(success: bool),
    mounted_image_retrieved: qt_signal!(
        success: bool,
        is_locked: bool,
        sig: QByteArray,
        sig_length: u64
    ),
    installed_apps_retrieved: qt_signal!(apps: QVariantMap),
    app_icon_loaded: qt_signal!(bundle_id: QString, icon_data: QByteArray),
    battery_info_updated: qt_signal!(info: QString),
    disk_usage_retrieved: qt_signal!(success: bool, apps_usage: u64),
    install_ipa_init: qt_signal!(started: bool, state: QString),
    install_ipa_progress: qt_signal!(progress: f64, state: QString),
    enable_wifi_connections_result: qt_signal!(success: bool),

    udid: String,
    ios_version: u32,
    /*
    *    TODO: default cannot be implemented for
    *    DeviceServices, so we have to wrap inside Option
    */
    device : Option<DeviceServices>
}

impl ServiceManager {
    
    /* unwrap on self.device must 
    *  be safe as from_device literally 
    *  receives a device not an option */
    pub fn from_device(device : DeviceServices, udid : String, ios_version : u32) -> Self {
        Self { device: Some(device) , udid : udid, ios_version : ios_version ,..Default::default() }
    } 

    pub fn start_update_battery_info_interval(&self) {
        let udid = self.udid.clone();
        let qt_thread = self.qt_thread();
        println!("Starting battery info update interval for device {udid}");
        RUNTIME.spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(30));

            loop {
                interval.tick().await;

                let maybe_device = get_device_opt(udid.as_str()).await;

                let device = match maybe_device {
                    Some(d) => d,
                    None => {
                        println!("Battery info interval: Device {udid} not found");
                        return;
                    }
                };

                println!("Battery info interval: Fetching battery info for device {udid}");

                utils::get_battery_info(&mut *device.diag.lock().await)
                    .await
                    .map(|info| {
                        let mut buf = Vec::new();
                        if Value::Dictionary(info).to_writer_xml(&mut buf).is_ok() {
                            if let Ok(s) = String::from_utf8(buf) {
                                qt_thread
                                    .queue(move |t| {
                                        t.battery_info_updated(QString::from(s));
                                    });
                            }
                        }
                    });
            }
        });
    }

    fn query_mobilegestalt(&self, keys: QStringList) {
        let udid = self.udid.clone();
        let qt_t = self.qt_thread();
        let keys_owned = keys.clone();
        let diag = self.device.as_ref().unwrap().clone().diag;
        RUNTIME.spawn(async move {
            let mut map = QVariantMap::default();

            let keys_vec: Vec<String> = keys_owned
                .into_iter()
                .map(|qstr| qstr.to_string())
                .collect();
            let qt_thread = qt_t.clone();
            let result = diag.lock().await.mobilegestalt(Some(keys_vec)).await;

            match result {
                Ok(opt_dict) => {
                    if let Some(mut root_dict) = opt_dict {
                         let mobilegestalt_value = root_dict.remove("MobileGestalt");

                         let inner_mobilegestalt_dict = match mobilegestalt_value {
                            Some(Value::Dictionary(dict)) => dict, 
                            _ => {
                                eprintln!(
                                    "query_mobilegestalt: MobileGestalt key not found or not a dictionary for device {udid}."
                                );
                                let _ = qt_thread.queue(move |t| {
                                    t.mobilegestalt_info_retrieved(map);
                                });
                                return;
                            }
                        };

                        for (k, v) in inner_mobilegestalt_dict.into_iter() {
                            let v_str = format!("{v:?}");
                            map.insert(QString::from(k), QVariant::from(&QString::from(v_str)));
                        }
                    }
                    let _ = qt_thread.queue(move |t| {
                        t.mobilegestalt_info_retrieved(map);
                    });
                }
                Err(e) => {
                    eprintln!(
                        "query_mobilegestalt: error querying MobileGestalt for device {udid}: {e}"
                    );
                    let _ = qt_thread.queue(move |t| {
                        t.mobilegestalt_info_retrieved(map);
                    });
                }
            }
        });
    }

    fn get_cable_info(&self) {
        let udid = self.udid.clone();
        let qt_t = self.qt_thread();

        let diag = self.device.as_ref().unwrap().clone().diag;
        RUNTIME.spawn(async move {
            let qt_thread = qt_t.clone();
            let res = utils::get_cable_info(&mut *diag.lock().await).await;

            match res {
                Some(dict) => {
                    let mut buf = Vec::new();
                    // ditch this, and return map instead
                    if Value::Dictionary(dict).to_writer_xml(&mut buf).is_err() {
                        eprintln!(
                            "get_cable_info: Failed to serialize ioregistry values to XML for device {udid}."
                        );
                        let _ = qt_thread.queue(|t| {
                            t.cable_info_retrieved(QString::from(""));
                        });
                        return;
                    }

                    match String::from_utf8(buf) {
                        Ok(s) => {
                            let _ = qt_thread.queue(move |t| {
                                t.cable_info_retrieved(QString::from(s));
                            });
                        }
                        Err(_) => {
                            eprintln!(
                                "get_cable_info: Failed to convert ioregistry XML data to string for device {udid}."
                            );
                            let _ = qt_thread.queue(|t| {
                                t.cable_info_retrieved(QString::from(""));
                            });
                        }
                    }
                }
                None => {
                    eprintln!("get_cable_info: Failed to get ioregistry for device {udid}");
                    let _ = qt_thread.queue(|t| {
                        t.cable_info_retrieved(QString::from(""));
                    });
                }
            }
        });
    }
    fn mount_dev_image(&self, image_path: QString, sig: QString) {
        let udid = self.udid.clone();
        let qt_t = self.qt_thread();
        let image = image_path.to_string();
        let signature = sig.to_string();

        let provider_guard = self.device.as_ref().unwrap().clone().provider;
        RUNTIME.spawn(async move {
            let qt_thread = qt_t.clone();
            let provider = provider_guard.lock().await;

            let mut mounter = match {
                let provider_ref: &dyn IdeviceProvider = provider.as_ref();
                ImageMounter::connect(provider_ref).await
            } {
                Ok(m) => m,
                Err(e) => {
                    eprintln!("mount_dev_image: Failed to connect to ImageMounter for device {udid}: {e}");
                    let _ = qt_thread.queue(|t| {
                        t.dev_image_mounted(false,false);
                    });
                    return;
                }
            };

            let mut file = match std::fs::File::open(&image) {
                Ok(f) => f,
                Err(e) => {
                    eprintln!("mount_dev_image: Failed to open image file {image} for device {udid}: {e}");
                    let _ = qt_thread.queue(|t| {
                        t.dev_image_mounted(false,false);
                    });
                    return;
                }
            };
            let mut buf = Vec::new();
            if let Err(e) = file.read_to_end(&mut buf) {
                eprintln!("mount_dev_image: Failed to read image file {image} for device {udid}: {e}");
                let _ = qt_thread.queue(|t| {
                    t.dev_image_mounted(false,false);
                });
                return;
            }

            let mut sig_file = match std::fs::File::open(&signature) {
                Ok(f) => f,
                Err(e) => {
                    eprintln!("mount_dev_image: Failed to open signature file {signature} for device {udid}: {e}");
                    let _ = qt_thread.queue(|t| {
                        t.dev_image_mounted(false,false);
                    });
                    return;
                }
            };

            let mut sig_buf: Vec<u8> = Vec::new();
            if let Err(e) = sig_file.read_to_end(&mut sig_buf) {
                eprintln!("mount_dev_image: Failed to read signature file {signature} for device {udid}: {e}");
                let _ = qt_thread.queue(|t| {
                    t.dev_image_mounted(false,false);
                });
                return;
            }

            match mounter.mount_developer(&buf, sig_buf).await {
                Ok(_) => {
                    let _ = qt_thread.queue(|t| {
                        t.dev_image_mounted(true ,false);
                    });
                }
                Err(idevice::IdeviceError::DeviceLocked) => {
                    eprintln!("mount_dev_image: Failed to mount developer image for device {udid}: device locked");
                    qt_thread.queue(|t| {
                        t.dev_image_mounted(false,true);
                    });
                }
                Err(e) => {
                    eprintln!("mount_dev_image: Failed to mount developer image for device {udid}: {e}");
                    qt_thread.queue(|t| {
                        t.dev_image_mounted(false,false);
                    });
                }
            };

        });
    }

    fn get_mounted_image(&self) {
        let udid = self.udid.clone();
        let qt_t = self.qt_thread();

        let provider_guard = self.device.as_ref().unwrap().clone().provider;

        RUNTIME.spawn(async move {
            let qt_thread = qt_t.clone();

            let mut mounter = match {
                let provider = provider_guard.lock().await;

                let provider_ref: &dyn IdeviceProvider = provider.as_ref();
                ImageMounter::connect(provider_ref).await
            } {
                Ok(m) => m,
                Err(e) => {
                    eprintln!("get_mounted_image: Failed to connect to ImageMounter for device {udid}: {e}");
                    qt_thread.queue(|t| {
                        t.mounted_image_retrieved(false,false,QByteArray::default(), 0);
                    });
                    return;
                }
            };

            match mounter.lookup_image("Developer").await {
                Ok(res) => {
                    qt_thread.queue(move|t| {
                        t.mounted_image_retrieved(true,false,QByteArray::from(&res[..]), res.len() as u64);
                    });
                }
                Err(idevice::IdeviceError::DeviceLocked) => {
                    eprintln!("get_mounted_image: Failed to lookup mounted developer image for device {udid}: device locked");
                    qt_thread.queue(|t| {
                        t.mounted_image_retrieved(false,true,QByteArray::default(), 0);
                    }); 
                }
                Err(idevice::IdeviceError::NotFound) => {
                    eprintln!("get_mounted_image: No mounted developer image found for device {udid}");
                    let _ = qt_thread.queue(|t| {
                        t.mounted_image_retrieved(true,false,QByteArray::default(), 0);
                    });
                }
                Err(e) => {
                    eprintln!("get_mounted_image: Failed to lookup mounted developer image for device {udid}: {e}");
                    let _ = qt_thread.queue(|t| {
                        t.mounted_image_retrieved(false,false,QByteArray::default(), 0);
                    });
                }
            };

        });
    }

    fn reveal_developer_mode_option_in_ui(&self) {
        let udid = self.udid.clone();
        let qt_t = self.qt_thread();


        let provider_guard = self.device.as_ref().unwrap().clone().provider;

        RUNTIME.spawn(async move {
            let qt_thread = qt_t.clone();
            
            let mut amfi_client = match {
                let provider_guard = provider_guard.lock().await;
                let provider_ref: &dyn IdeviceProvider = provider_guard.as_ref();
                amfi::AmfiClient::connect(provider_ref).await
            } {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("reveal_developer_mode_option_in_ui: Failed to connect to AMFI service for device {udid}: {e}");
                    let _ = qt_thread.queue(|t| {
                        t.developer_mode_option_revealed(false);
                    });
                    return;
                }
            };


            match amfi_client.reveal_developer_mode_option_in_ui().await {
                Ok(_) => {
                    let _ = qt_thread.queue(|t| {
                        t.developer_mode_option_revealed(true);
                    });
                }
                Err(e) => {
                    eprintln!("reveal_developer_mode_option_in_ui: Failed to reveal developer mode option in UI for device {udid}: {e}");
                    let _ = qt_thread.queue(|t| {
                        t.developer_mode_option_revealed(false);
                    });
            }

            }
        });
    }

    fn fetch_installed_apps(&self) {
        let udid = self.udid.clone();
        let qt_t = self.qt_thread();

        let provider_guard = self.device.as_ref().unwrap().clone().provider;

        RUNTIME.spawn(async move {
            let qt_thread = qt_t.clone();
            
            let mut all_apps = QVariantMap::default();

        
            let mut ins_client = match {
                let provider_guard = provider_guard.lock().await;
                let provider_ref: &dyn IdeviceProvider = provider_guard.as_ref();
                InstallationProxyClient::connect(provider_ref).await
            } {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("fetch_installed_apps: Failed to connect to InstallationProxy service for device {udid}: {e}");
                    let _ = qt_thread.queue( move |t| {
                        t.installed_apps_retrieved(all_apps);
                    });
                    return;
                }
            };

            // Get both User and System apps
            for app_type in ["User", "System"] {
                let client_options = plist!({
                    "ApplicationType": app_type,
                    "ReturnAttributes": [
                        "CFBundleIdentifier",
                        "CFBundleDisplayName",
                        "CFBundleShortVersionString",
                        "CFBundleVersion",
                        "UIFileSharingEnabled"
                    ]
                });

                let apps = match ins_client.browse(Some(client_options)).await {
                    Ok(apps) => apps,
                    Err(e) => {
                        eprintln!("fetch_installed_apps: Failed to browse installed apps for device {udid} and app type {app_type}: {e}");
                        continue; // Skip this app type 
                    }
                };

                for app_info in apps {
                    if let plist::Value::Dictionary(app_dict) = app_info {
                        let bundle_id = app_dict
                            .get("CFBundleIdentifier")
                            .and_then(|v| v.as_string())
                            .unwrap_or_default();

                        if bundle_id.is_empty() {
                            continue;
                        }

                        let display = app_dict
                            .get("CFBundleDisplayName")
                            .and_then(|v| v.as_string())
                            .unwrap_or_default();
                        let version = app_dict
                            .get("CFBundleShortVersionString")
                            .and_then(|v| v.as_string())
                            .unwrap_or_default();
                        let fs_enabled = app_dict
                            .get("UIFileSharingEnabled")
                            .and_then(|v| v.as_boolean())
                            .unwrap_or(false);

                        let app_json = format!(
                            "{{\"bundle_id\":{},\"CFBundleDisplayName\":{},\"CFBundleShortVersionString\":{},\"UIFileSharingEnabled\":{},\"app_type\":{}}}",
                            serde_json::to_string(&bundle_id).unwrap_or_else(|_| format!("\"{}\"", bundle_id)),
                            serde_json::to_string(&display).unwrap_or_else(|_| format!("\"{}\"", display)),
                            serde_json::to_string(&version).unwrap_or_else(|_| format!("\"{}\"", version)),
                            fs_enabled,
                            serde_json::to_string(&app_type).unwrap_or_else(|_| format!("\"{}\"", app_type)),
                        );

                        all_apps.insert(
                            QString::from(bundle_id),
                            QVariant::from(&QString::from(app_json)),
                        );
                    }
                }
            }

            let _ = qt_thread.queue(move |t| {
                t.installed_apps_retrieved(all_apps);
            });
        });
    }

    fn fetch_app_icon(&self, bundle_id: QString) {
        let udid = self.udid.clone();
        let qt_t = self.qt_thread();
        let bundle_id_owned = bundle_id.clone();


        let provider_guard = self.device.as_ref().unwrap().clone().provider;

        RUNTIME.spawn(async move {
           
            let mut springboard_client = match {
                let provider_guard = provider_guard.lock().await;
                let provider_ref: &dyn IdeviceProvider = provider_guard.as_ref();
                SpringBoardServicesClient::connect(provider_ref).await
            } {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("fetch_app_icon: Failed to connect to InstallationProxy service for device {udid}: {e}");
                    return;
                }
            };

            match springboard_client.get_icon_pngdata(bundle_id_owned.to_string()).await {
                Ok(icon_data) => {
                    qt_t.queue(move |t| {
                        t.app_icon_loaded(bundle_id_owned, QByteArray::from(&icon_data[..]));
                    });
                }
                Err(e) => {
                    eprintln!("fetch_app_icon: Failed to fetch app icon for bundle ID {} on device {udid}: {e}", bundle_id_owned);
                }
            };
        });
    }

    fn set_location(&self, latitude: QString, longitude: QString) -> i32 {
        let udid = self.udid.clone();
        let ios_version = self.ios_version;

        let provider_guard = self.device.as_ref().unwrap().clone().provider;
        /*
            FIXME: use RUNTIME.spawn in the future
        */
        RUNTIME.block_on(async move {
            tokio::select! {
                res = async {
                    let result = {
                        let provider_guard = provider_guard.lock().await;


                        if ios_version < 17 {
                            set_device_location_lockdown( provider_guard.as_ref(), latitude.to_string().as_str(), longitude.to_string().as_str()).await
                        } else {
                            println!("Using RSD path for setting location on device {udid} with iOS version {ios_version}");
                            let proxy_res = {
                                CoreDeviceProxy::connect(provider_guard.as_ref()).await
                            };

                            match proxy_res {
                                Ok(proxy) => set_device_location_rsd(proxy, utils::qstring_to_f64(latitude).unwrap_or(0.0), utils::qstring_to_f64(longitude).unwrap_or(0.0)).await,
                                Err(err) => {
                                    println!("Failed to connect to CoreDeviceProxy for device {udid}, cannot set location using RSD path.");
                                    return err.code();
                                },
                            }
                        }
                    };

                    match result {
                        Ok(_) => 0,
                        Err(e) => {
                            eprintln!(
                                "set_location: failed to set virtual location for device {udid}: {e:?}"
                            );
                            return e.code();
                        }
                    }
                } => {
                    res
                }
                _ = tokio::time::sleep(Duration::from_secs(10)) => {
                    eprintln!("set_location: timed out");
                    idevice::IdeviceError::Timeout.code()
                }
            }
        })
    }

    fn fetch_disk_usage(&self) {
        let udid = self.udid.clone();
        let qt_t = self.qt_thread();

        let provider_guard = self.device.as_ref().unwrap().clone().provider;

        RUNTIME.spawn(async move {
            let qt_thread = qt_t.clone();

            let mut instproxy = {                
                let provider_guard = provider_guard.lock().await;

                match InstallationProxyClient::connect(provider_guard.as_ref()).await {
                    Ok(c) => c,
                    Err(e) => {
                        eprintln!("fetch_disk_usage: Failed to connect to InstallationProxy service for device {udid}: {e}");
                        qt_thread.queue(move |t| {
                            t.disk_usage_retrieved(false, 0);
                        });
                        return;
                    }
                }
            };
            

            match utils::calculate_apps_usage(&mut instproxy).await {
                Ok(apps_usage) => {                    
                    qt_thread.queue(move |t| {
                        t.disk_usage_retrieved(true, apps_usage);
                    });
                }
                Err(e) => {
                    eprintln!("fetch_disk_usage: Failed to calculate apps disk usage for device {udid}: {e}");
                    qt_thread.queue(move |t| {
                        t.disk_usage_retrieved(false, 0);
                    });
                }
            };
        

        });
    }

    fn restart(&self) -> bool {
        let udid = self.udid.clone();

        let diag_guard = self.device.as_ref().unwrap().clone().diag;

        run_sync(async move {
            let mut diag = diag_guard.lock().await;

            if let Err(e) = diag.restart().await {
                eprintln!("restart: Failed to restart device {udid}: {e}");
                return false;
            }
            return true;
        })
    }

    fn shutdown(&self) -> bool {
        let udid = self.udid.clone();

        let diag_guard = self.device.as_ref().unwrap().clone().diag;
        run_sync(async move {
            let mut diag = diag_guard.lock().await;
            

            if let Err(e) = diag.shutdown().await {
                eprintln!("shutdown: Failed to shutdown device {udid}: {e}");
                return false;
            }
            return true;
        })
    }
    fn enter_recovery_mode(&self) -> bool {
        let udid = self.udid.clone();

        let lc_guard = self.device.as_ref().unwrap().clone().lockdown;
        run_sync(async move {
            let mut lc = lc_guard.lock().await;

            if let Err(e) = lc.enter_recovery().await {
                eprintln!(
                    "enter_recovery_mode: Failed to enter recovery mode for device {udid}: {e}"
                );
                return false;
            }
            return true;
        })
    }

    fn install_ipa(&self, local_ipa_path: QString) {
        let udid = self.udid.clone();
        let qt_t = self.qt_thread();
        let local_ipa_path_owned = local_ipa_path.clone().to_string();
        // FIXME: this is a bit hacky
        let ipa_path_on_device = format!(
            "/PublicStaging/{}",
            local_ipa_path
                .to_string()
                .split('/')
                .last()
                .unwrap_or("app.ipa")
        );
        let cloned = self.device.as_ref().unwrap().clone();
        let afc_guard = cloned.afc;
        let provider_guard = cloned.provider;

        RUNTIME.spawn(async move {
            let qt_thread = qt_t.clone();
            
            let mut ins_client = match {

                let mut afc = afc_guard.lock().await;
                
                // Create the staging directory
                match utils::ensure_public_staging(&mut afc).await {
                    Ok(_) => (),
                    Err(e) => {
                        eprintln!("install_ipa: Failed to ensure /PublicStaging directory exists on device {udid}: {e}");
                        qt_thread.queue(move |t| {
                            t.install_ipa_init(false, QString::from("Failed to prepare device for IPA upload"));
                        });
                        return;
                    }
                };

                match std::fs::exists(&local_ipa_path_owned)  {
                    Ok(true) => (),
                    Ok(false) => {
                        eprintln!("install_ipa: IPA file not found at path {local_ipa_path_owned}");
                        qt_thread.queue(move |t| {
                            t.install_ipa_init(false, QString::from("IPA file not found"));
                        });
                        return;
                    }
                    Err(e) => {
                        eprintln!("install_ipa: Failed to check if IPA file exists at path {local_ipa_path_owned}: {e}");
                        qt_thread.queue(move |t| {
                            t.install_ipa_init(false, QString::from("Failed to access IPA file"));
                        });
                        return;
                    }
                }



                match afc.open(&ipa_path_on_device, AfcFopenMode::WrOnly).await {
                    Ok(mut fd) => {
                        let mut local_file = match std::fs::File::open(&local_ipa_path_owned) {
                            Ok(f) => f,
                            Err(e) => {
                                eprintln!("install_ipa: Failed to open local IPA file for device {udid}: {e}");
                                qt_thread.queue(move |t| {
                                    t.install_ipa_init(false, QString::from("Failed to open local IPA file"));
                                });
                                return;
                            }
                        };

                        let mut file_btytes = Vec::new();
                        match local_file.read_to_end(&mut file_btytes) {
                            Ok(bytes) => bytes,
                            Err(e) => {
                                eprintln!("install_ipa: Failed to read local IPA file for device {udid}: {e}");
                                qt_thread.queue(move |t| {
                                    t.install_ipa_init(false, QString::from("Failed to read local IPA file"));
                                });
                                return;
                            }
                        };

                        if let Err(e) = fd.write_entire(&file_btytes).await {
                            eprintln!("install_ipa: Failed to upload IPA to device {udid}: {e}");
                            qt_thread.queue(move |t| {
                                t.install_ipa_init(false, QString::from("Failed to upload IPA to device"));
                            });
                            return;
                        }
                    }
                    Err(e) => {
                        eprintln!("install_ipa: Failed to create file on device {udid} for IPA upload: {e}");
                        qt_thread.queue(move |t| {
                            t.install_ipa_init(false, QString::from("Failed to create file on device for IPA upload"));
                        });
                        return;
                    }
                }


                let provider_guard = provider_guard.lock().await;
                let provider_ref: &dyn IdeviceProvider = provider_guard.as_ref();
                InstallationProxyClient::connect(provider_ref).await
            } {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("install_ipa: Failed to connect to InstallationProxy service for device {udid}: {e}");
                    qt_thread.queue(move |t| {
                        t.install_ipa_init(false, QString::from("Failed to connect to Installation Proxy"));
                    });
                    return;
                }
            };

            qt_thread.queue(move |t| {
                t.install_ipa_init(true, QString::from("Connected to Installation Proxy"));
            });

            let state = String::from("Installing IPA");

            let res = ins_client
                .install_with_callback(
                    ipa_path_on_device,
                    None,
                    move |(percent, state)| {
                        let qt_thread = qt_thread.clone();
                        async move {
                            let progress = percent as f64 / 100.0;

                            qt_thread
                                .queue(move |t| {
                                    t.install_ipa_progress(
                                        progress,
                                        QString::from(state),
                                    );
                                });

                            println!(
                                "Installation progress: {percent}%"
                            );
                        }
                    },
                    state,
                )
                .await;

            if let Err(e) = res {
                eprintln!("install_ipa: Failed to install IPA on device {udid}: {e}");
            } else {
                println!("install_ipa: Successfully initiated installation on device {udid}");
            }
        });
    }

    fn enable_wifi_connections(&self) {
        let qt_t = self.qt_thread();
        let udid = self.udid.clone();

        let lc_guard = self.device.as_ref().unwrap().clone().lockdown;
        RUNTIME.spawn(async move {
            let qt_thread = qt_t.clone();


            let mut lc = lc_guard.lock().await;

            let value = Value::Boolean(true);
            match lc
                .set_value(
                    "EnableWifiConnections",
                    value,
                    Some("com.apple.mobile.wireless_lockdown"),
                )
                .await
            {
                Ok(_) => {
                    let _ = qt_thread
                        .queue(|t| {
                            t.enable_wifi_connections_result(true);
                        });
                }
                Err(e) => {
                    eprintln!("wireless: LockdownClient::set_value failed: {e:?} udid: {udid}");
                    let _ = qt_thread
                        .queue(|t| {
                            t.enable_wifi_connections_result(false);
                        });
                }
            }
        });
    }
}

async fn set_device_location_lockdown(
    provider: &dyn IdeviceProvider,
    latitude: &str,
    longitude: &str,
) -> Result<(), idevice::IdeviceError> {
    let mut client = LocationSimulationService::connect(provider).await?;
    client.set(latitude, longitude).await
}

// iOS 17+:
async fn set_device_location_rsd(
    proxy: CoreDeviceProxy,
    latitude: f64,
    longitude: f64,
) -> Result<(), idevice::IdeviceError> {
    let rsd_port = proxy.tunnel_info().server_rsd_port;
    let adapter = proxy.create_software_tunnel()?;
    let mut adapter = adapter.to_async_handle();
    let stream = adapter.connect(rsd_port).await?;

    let mut handshake = RsdHandshake::new(stream).await?;

    let mut remote_server = RemoteServerClient::connect_rsd(&mut adapter, &mut handshake).await?;
    remote_server.read_message(0).await?;

    let mut location_client = LocationSimulationClient::new(&mut remote_server).await?;
    location_client.set(latitude, longitude).await
}
