use idevice::IdeviceService;
use idevice::mobile_image_mounter::ImageMounter;
use idevice::provider::IdeviceProvider;
use log::{debug, error, info, warn};
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::Write;
use std::path::{self, Path, PathBuf};
use std::sync::Arc;

use crate::list_model::ListModel;
use crate::{
    RUNTIME,
    qt_threading::{QtThread, QtThreading},
    qvariantmap_insert,
};
use futures::StreamExt;
use macros::QtThreading;
use qmetaobject::SimpleListItem;
use qmetaobject::prelude::*;
use qttypes::{QString, QVariantMap};
use reqwest::Client;
use std::cell::RefCell;
use tokio::io::AsyncWriteExt;
use tokio::task::JoinHandle;

#[derive(SimpleListItem, Default, Clone)]
struct DiskImageItem {
    pub version: QString,
    pub compatibility: QString,
    pub is_mounted: bool,
    pub is_downloaded: bool,
    pub progress: f64,
    pub is_downloading: bool,
}

#[derive(QObject, Default, QtThreading)]
pub struct DevImgsManager {
    base: qt_base_class!(trait QObject),
    image_download_finished: qt_signal!(version: QString, index: u32, success: bool, error: QString),
    image_list: qt_property!(QVariantMap; NOTIFY image_list_changed),
    image_list_changed: qt_signal!(),
    mounted_image_info: qt_property!(QVariantMap; NOTIFY mounted_image_info_changed),
    mounted_image_info_changed: qt_signal!(),
    activate_downloads: std::sync::Mutex<HashMap<String, JoinHandle<()>>>,
    download_image: qt_method!(fn(version: QString, index: u32) -> bool),
    state: qt_property!(QString; NOTIFY state_changed),
    state_changed: qt_signal!(),
    fetch_image_list: qt_method!(fn(udid: QString)),
    handle_download_finished: qt_method!(fn(version: QString)),
    download_progress_for_index: qt_signal!(index: u32, version: QString, progress: f64),
    cancel_download: qt_method!(fn(version: QString)),
    get_locations_for_version: qt_method!(fn(version: QString) -> QVariantMap),
    get_best_compatible_version: qt_method!(fn(ios_major: u32) -> QVariantMap),

    image_model: qt_property!(RefCell<ListModel<DiskImageItem>>; NOTIFY image_model_changed),
    image_model_changed: qt_signal!(),
    get_item: qt_method!(fn(index: i32) -> QVariantMap),
    check_mounted_image: qt_method!(fn(udid: QString)),
}

// FIXME:hardcoded
pub const IMG_BASE_PATH: &str = "./DeveloperDiskImages/";

impl DevImgsManager {
    pub fn parse_disk_dir() -> HashMap<String, bool> {
        let mut res = HashMap::new();
        let path = Path::new(IMG_BASE_PATH);
        if !path.exists() {
            return res;
        }

        //list dir and make sure .dmg and .dmg.signature exist for each version
        for entry in fs::read_dir(path).unwrap() {
            let entry = entry.unwrap();
            let path = entry.path();
            if path.is_dir() {
                let version = path.file_name().unwrap().to_str().unwrap().to_string();
                let dmg_path = path.join("DeveloperDiskImage.dmg");
                let sig_path = path.join("DeveloperDiskImage.dmg.signature");
                // maybe assign false if one of the files is missing,
                // but for now just ignore it, as redownloading is possible
                if dmg_path.exists() && sig_path.exists() {
                    res.insert(version, true);
                }
            }
        }

        res
    }

    // udid is need, so we can check if the device has
    // a developer disk image mounted
    pub fn fetch_image_list(&mut self, udid: QString) {
        let qt_thread = self.qt_thread();
        let get_mounted_image = Self::get_mounted_image(udid.clone());

        RUNTIME.spawn(async move {
            let result: anyhow::Result<()> = async {
                let data = crate::dev_imgs::get().await?;
                let parsed_disk_dir = DevImgsManager::parse_disk_dir();
                let mounted_image = get_mounted_image.await;
                let dev = crate::device_ctx::get_device(udid.clone()).await;

                let (should_compare_signatures, mounted_sig) = match mounted_image {
                    Ok((success, _is_locked, data)) => (success && !data.is_empty(), data),
                    Err(e) => {
                        warn!(
                            "Error fetching mounted image info for device {}: {}",
                            udid.to_string(),
                            e
                        );
                        (false, Vec::new())
                    }
                };

                // (u32, u32) = (major, minor)
                let device_version: Option<(u32, u32)> = match dev {
                    Ok(dev) => dev
                        .ios_version
                        .split('.')
                        .take(2)
                        .map(|s| s.parse::<u32>().ok())
                        .collect::<Option<Vec<u32>>>()
                        .and_then(|v| {
                            if v.len() == 2 {
                                Some((v[0], v[1]))
                            } else {
                                None
                            }
                        }),
                    Err(e) => {
                        warn!(
                            "Error fetching device info for device {}: {}",
                            udid.to_string(),
                            e
                        );
                        None
                    }
                };

                qt_thread.queue(move |q| {
                    // compatibility priority: 0 = exact, 1 = same major, 2 = incompatible, 3 = no device
                    let compat_priority = |item: &DiskImageItem| -> u8 {
                        match device_version {
                            None => 3,
                            Some((maj, min)) => {
                                let v = item.version.to_string();
                                let mut parts = v.splitn(2, '.');
                                let item_maj = parts
                                    .next()
                                    .and_then(|s| s.parse::<u32>().ok())
                                    .unwrap_or(0);
                                let item_min = parts
                                    .next()
                                    .and_then(|s| s.parse::<u32>().ok())
                                    .unwrap_or(0);

                                if item_maj == maj && item_min == min {
                                    0
                                } else if item_maj == maj {
                                    1
                                } else {
                                    2
                                }
                            }
                        }
                    };

                    let compat_label = |priority: u8| -> &'static str {
                        match priority {
                            0 => "Compatible",
                            1 => "MaybeCompatible",
                            2 => "Incompatible",
                            _ => "No device",
                        }
                    };

                    let mut items: Vec<DiskImageItem> = data
                        .iter()
                        .map(|(version, _)| {
                            let is_mounted = if should_compare_signatures {
                                crate::utils::compare_signatures(version, &mounted_sig)
                            } else {
                                false
                            };
                            DiskImageItem {
                                version: version.to_string().into(),
                                is_downloaded: parsed_disk_dir.contains_key(version),
                                is_mounted,
                                ..Default::default()
                            }
                        })
                        .collect();

                    // sort: compatibility first, then version descending within each group
                    items.sort_by(|a, b| {
                        let pa = compat_priority(a);
                        let pb = compat_priority(b);
                        pa.cmp(&pb).then_with(|| {
                            // descending version sort: compare b vs a
                            let parse = |s: &str| -> (u32, u32) {
                                let mut p = s.splitn(2, '.');
                                let maj = p.next().and_then(|x| x.parse().ok()).unwrap_or(0);
                                let min = p.next().and_then(|x| x.parse().ok()).unwrap_or(0);
                                (maj, min)
                            };
                            let va = parse(&a.version.to_string());
                            let vb = parse(&b.version.to_string());
                            vb.cmp(&va) // reversed for descending
                        })
                    });

                    // stamp compatibility label now that order is resolved
                    for item in &mut items {
                        let p = compat_priority(item);
                        item.compatibility = compat_label(p).into();
                    }

                    q.image_model.borrow_mut().reset_data(items);
                });

                Ok(())
            }
            .await;
        });
    }

    fn check_mounted_image(&mut self, udid: QString) {
        let qt_thread = self.qt_thread();
        RUNTIME.spawn(async move {
            let result = Self::get_mounted_image(udid.clone()).await;
            match result {
                Ok((is_mounted, is_locked, data)) => {
                    let mut map = QVariantMap::default();
                    qvariantmap_insert!(map, "is_mounted", is_mounted);
                    qvariantmap_insert!(map, "is_locked", is_locked);
                    qvariantmap_insert!(map, "signature", QString::from(hex::encode(data)));
                    qt_thread.queue(move |q| {
                        q.mounted_image_info = map;
                    });
                }
                Err(e) => {
                    error!(
                        "check_mounted_image: Failed to check mounted image for device {}: {}",
                        udid.to_string(),
                        e
                    );
                }
            }
        });
    }

    fn get_item(&self, index: i32) -> QVariantMap {
        let mut map = QVariantMap::default();
        if index < 0 {
            return map;
        }

        let model = self.image_model.borrow();
        let Some(item) = model.values.get(index as usize) else {
            return map;
        };

        qvariantmap_insert!(map, "version", item.version.clone());
        qvariantmap_insert!(map, "compatibility", item.compatibility.clone());
        qvariantmap_insert!(map, "is_mounted", item.is_mounted);
        qvariantmap_insert!(map, "is_downloaded", item.is_downloaded);
        qvariantmap_insert!(map, "progress", item.progress);
        qvariantmap_insert!(map, "is_downloading", item.is_downloading);
        map
    }

    async fn get_mounted_image(udid: QString) -> anyhow::Result<(bool, bool, Vec<u8>)> {
        let dev = crate::device_ctx::get_device(udid.clone()).await?;
        let provider_guard = dev.clone().provider;

        let mut mounter = async {
            let provider = provider_guard.lock().await;
            let provider_ref: &dyn IdeviceProvider = provider.as_ref();
            ImageMounter::connect(provider_ref).await
        }
        .await?;

        match mounter.lookup_image("Developer").await {
            Ok(res) => {
                return Ok((true, false, res));
            }
            Err(idevice::IdeviceError::DeviceLocked) => {
                eprintln!(
                    "get_mounted_image: Failed to lookup mounted developer image for device {udid}: device locked"
                );
                return Ok((false, true, Vec::new()));
            }
            Err(idevice::IdeviceError::NotFound) => {
                eprintln!("get_mounted_image: No mounted developer image found for device {udid}");
                return Ok((false, false, Vec::new()));
            }
            Err(e) => {
                eprintln!(
                    "get_mounted_image: Failed to lookup mounted developer image for device {udid}: {e}"
                );
                return Ok((false, false, Vec::new()));
            }
        };
    }

    pub fn cancel_download(&mut self, version: QString) {
        let version_str = version.to_string();
        let mut downloads = self.activate_downloads.lock().unwrap();
        if let Some(handle) = downloads.remove(&version_str) {
            handle.abort();
            info!("Download for version {} has been cancelled.", version_str);
        } else {
            warn!(
                "No active download found for version {} to cancel.",
                version_str
            );
        }
    }

    // TODO: maybe we can do better here
    // Will be called from QML side when a download is finished
    // this avoids using Arc on activate_downloads
    pub fn handle_download_finished(&mut self, version: QString) {
        self.activate_downloads
            .lock()
            .unwrap()
            .remove(&version.to_string());
    }

    pub fn get_locations_for_version(&self, version: QString) -> QVariantMap {
        let mut map = QVariantMap::default();
        let version_str = version.to_string();
        let base_path = PathBuf::from(IMG_BASE_PATH);
        let version_path = base_path.join(&version_str);
        let dmg_path = version_path.join("DeveloperDiskImage.dmg");
        let sig_path = version_path.join("DeveloperDiskImage.dmg.signature");

        qvariantmap_insert!(
            map,
            "dmg",
            QString::from(dmg_path.to_str().unwrap_or_default())
        );
        qvariantmap_insert!(
            map,
            "sig",
            QString::from(sig_path.to_str().unwrap_or_default())
        );
        qvariantmap_insert!(map, "exists", dmg_path.exists() && sig_path.exists());

        map
    }

    pub fn get_best_compatible_version(&self, ios_major: u32) -> QVariantMap {
        let mut map = QVariantMap::default();
        qvariantmap_insert!(map, "version", QString::default());
        qvariantmap_insert!(map, "exists", false);
        qvariantmap_insert!(map, "found", false);

        let images = match crate::run_sync(async { crate::dev_imgs::get().await }) {
            Ok(images) => images,
            Err(e) => {
                warn!(
                    "get_best_compatible_version: failed to fetch image list for iOS {}: {}",
                    ios_major, e
                );
                return map;
            }
        };

        let mut versions: Vec<(u32, u32, String)> = images
            .keys()
            .filter_map(|version| {
                let mut parts = version.splitn(2, '.');
                let major = parts.next()?.parse::<u32>().ok()?;
                let minor = parts
                    .next()
                    .and_then(|part| part.parse::<u32>().ok())
                    .unwrap_or(0);

                if major == ios_major {
                    Some((major, minor, version.clone()))
                } else {
                    None
                }
            })
            .collect();

        versions.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| b.2.cmp(&a.2)));

        let Some((_, _, version)) = versions.into_iter().next() else {
            return map;
        };

        let version_path = PathBuf::from(IMG_BASE_PATH).join(&version);
        let exists = version_path.join("DeveloperDiskImage.dmg").exists()
            && version_path
                .join("DeveloperDiskImage.dmg.signature")
                .exists();

        qvariantmap_insert!(map, "version", QString::from(version));
        qvariantmap_insert!(map, "exists", exists);
        qvariantmap_insert!(map, "found", true);

        map
    }

    pub fn download_image(&mut self, version: QString, index: u32) -> bool {
        println!(
            "download_image called with version: {}",
            version.to_string()
        );
        let version_str = version.to_string();
        let mut downloads = self.activate_downloads.lock().unwrap();

        if downloads.contains_key(&version_str) {
            return false; // already in progress
        }

        // FIXME: dont block if possible
        let zip_url = crate::run_sync(async { crate::dev_imgs::get().await })
            .unwrap()
            .get(&version_str)
            .cloned()
            .unwrap_or_default()[0]
            .clone();

        let target_dir = PathBuf::from(format!("{}", IMG_BASE_PATH));
        if let Err(e) = fs::create_dir_all(&target_dir) {
            self.image_download_finished(
                version.clone(),
                index,
                false,
                QString::from(format!("Could not create directory: {}", e)),
            );
            return false;
        }

        let qt_thread = self.qt_thread();
        let url = zip_url.to_string();

        let handle = RUNTIME.spawn(async move {
            let result =
                download_and_extract(&version_str, &url, &target_dir, qt_thread.clone(), index)
                    .await;

            let (success, message) = match result {
                Ok(()) => (true, String::new()),
                Err(e) => (false, e.to_string()),
            };

            qt_thread.queue(move |q| {
                q.image_download_finished(
                    QString::from(version_str),
                    index,
                    success,
                    QString::from(message),
                );
            });
        });

        downloads.insert(version.to_string(), handle);
        true
    }
}

async fn download_and_extract(
    version: &str,
    url: &str,
    target_dir: &Path,
    qt_thread: QtThread<DevImgsManager>,
    index: u32,
) -> anyhow::Result<()> {
    // download with progress
    let client = Client::new();
    let response = client.get(url).send().await?;
    let total = response.content_length().unwrap_or(0);
    let mut downloaded: u64 = 0;

    let tmp_zip = target_dir.join(format!("img_{}.zip.tmp", version));
    let mut file = tokio::fs::File::create(&tmp_zip).await?;
    let mut stream = response.bytes_stream();

    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        file.write_all(&chunk).await?;
        downloaded += chunk.len() as u64;

        if total > 0 {
            let progress = (downloaded as f64 / total as f64) * 100.0;
            let version_str = version.to_string();
            qt_thread.queue(move |q| {
                // q.download_progress_for_index(index, QString::from(version_str), progress);
                q.image_model.borrow_mut().mutate(index as usize, |item| {
                    item.progress = progress;
                });
            });
        }
    }
    file.flush().await?;
    drop(file);

    let tmp_zip_std = tmp_zip.to_owned();
    let target_dir_owned = target_dir.to_owned();
    let version_owned = version.to_owned();
    println!("Extracting zip to {:?}", target_dir_owned);

    // zip extraction
    tokio::task::spawn_blocking(move || -> anyhow::Result<()> {
        let file = std::fs::File::open(&tmp_zip_std)?;
        let mut archive = zip::ZipArchive::new(file)?;
        archive.extract(&target_dir_owned)?;
        std::fs::remove_file(&tmp_zip_std)?;

        let extracted_path = PathBuf::from(format!("{}{}", IMG_BASE_PATH, version_owned));
        // validate expected files exist
        let dmg = extracted_path.join("DeveloperDiskImage.dmg");
        let sig = extracted_path.join("DeveloperDiskImage.dmg.signature");
        if !dmg.exists() || !sig.exists() {
            anyhow::bail!("Zip extracted but required files missing (.dmg or .dmg.signature)");
        }
        Ok(())
    })
    .await??;

    Ok(())
}
