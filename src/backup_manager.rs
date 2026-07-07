use crate::{
    RUNTIME,
    list_model::ListModel,
    qt_threading::{QtThread, QtThreading},
    qvariantmap_insert,
};
use idevice::{
    IdeviceError, IdeviceService,
    mobilebackup2::{
        BackupDelegate, DirEntryInfo, FsBackupDelegate, MobileBackup2Client, RestoreOptions,
    },
    provider::IdeviceProvider,
};
use log::{debug, error, info};
use macros::QtThreading;
use plist::Value;
use qmetaobject::{SimpleListItem, prelude::*};
use qttypes::{QString, QVariantMap};
use std::{
    cell::RefCell,
    collections::HashMap,
    future::Future,
    io::{Read, Write},
    path::{Path, PathBuf},
    pin::Pin,
    sync::{Arc, Mutex},
    time::{Duration, Instant, SystemTime},
};
use tokio::task::JoinHandle;
use tracing::field::debug;

#[derive(SimpleListItem, Default, Clone)]
struct BackupListItem {
    pub udid: QString,
    pub source: QString,
    pub device_name: QString,
    pub display_name: QString,
    pub last_backup: QString,
    pub version: QString,
    pub encrypted: bool,
    pub path: QString,
    pub status: QString,
}

#[derive(Debug, Clone)]
struct BackupInfo {
    udid: String,
    source: String,
    device_name: String,
    display_name: String,
    last_backup: String,
    version: String,
    encrypted: bool,
    path: String,
    status: String,
}

#[allow(non_snake_case)]
#[derive(QObject, Default, QtThreading)]
pub struct BackupManager {
    base: qt_base_class!(trait QObject),
    state: qt_property!(QVariantMap; NOTIFY state_changed),
    state_changed: qt_signal!(),
    busy: qt_property!(bool; NOTIFY busy_changed),
    busy_changed: qt_signal!(),
    backup_model: qt_property!(RefCell<ListModel<BackupListItem>>; NOTIFY backup_model_changed),
    backup_model_changed: qt_signal!(),
    progressUpdate: qt_signal!(udid: QString, progress: f64),
    operationFinished: qt_signal!(operation: QString, udid: QString, success: bool),
    backupInfoReady: qt_signal!(udid: QString, success: bool, res: QString),
    backupInfoReadyWithoutDevice: qt_signal!(udid: QString, success: bool, res: QString),
    fileReceived: qt_signal!(udid: QString, path: QString),
    init: qt_method!(fn(&mut self, backup_root_path: QString)),
    // refresh :
    does_backup_exist_for_udid: qt_method!(fn(&self, udid: QString) -> bool),
    get_backup_info: qt_method!(fn(&self, udid: QString, root: QString)),
    // refresh_backups: qt_method!(fn(&mut self, root: QString)),
    start_backup: qt_method!(fn(&mut self, root: QString, udid: QString)),
    start_restore: qt_method!(
        fn(
            &mut self,
            root: QString,
            udid: QString,
            password: QString,
            reboot: bool,
            copy: bool,
            preserve_settings: bool,
            system_files: bool,
            remove_items_not_restored: bool,
        )
    ),
    // erase_device: qt_method!(fn(&mut self, root: QString, udid: QString)),
    // cancel: qt_method!(fn(&mut self)),
    // is_init : bool,
    get_backup_info_without_device: qt_method!(fn(&self, udid: QString, root: QString)),
    cancel_operation: qt_method!(fn(&mut self, udid: String) -> bool),
    get_backup_metadata: qt_method!(fn(&self, udid: QString, root: QString) -> QVariantMap),
    tasks: HashMap<String, JoinHandle<()>>,
}

impl BackupManager {
    pub fn new_with_state() -> Self {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "success", false);
        qvariantmap_insert!(state, "loading", true);

        let mut manager = Self::default();
        manager.state = state;
        manager
    }

    // A very bad to verify but it'll do it for the most part
    fn is_backup_dir(path: &PathBuf) -> bool {
        let manifest_db = path.join("Manifest.db");
        let manifest_plist = path.join("Manifest.plist");
        let status_plist = path.join("Status.plist");
        path.is_dir() && manifest_db.exists() && manifest_plist.exists() && status_plist.exists()
    }

    fn set_loading(&mut self) {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "success", false);
        qvariantmap_insert!(state, "loading", true);
        self.state = state;
        self.state_changed();
    }

    // fn update_row(){}

    fn init(&mut self, backup_root_path: QString) {
        self.set_loading();
        let mut state = QVariantMap::default();
        let path = PathBuf::from(backup_root_path);

        let existing_backups: Vec<BackupListItem> = match std::fs::read_dir(&path) {
            Ok(entries) => {
                let entries = entries
                    .filter_map(|e| e.ok())
                    .map(|e| e.path())
                    .filter(|p| Self::is_backup_dir(p))
                    .map(|p| {
                        let mut item = BackupListItem::default();
                        // file_name is actually dir name here
                        item.udid = QString::from(p.file_name().unwrap().display().to_string());
                        item
                    })
                    .collect();

                qvariantmap_insert!(state, "success", true);
                qvariantmap_insert!(state, "loading", false);

                entries
            }
            Err(_) => {
                qvariantmap_insert!(state, "success", false);
                qvariantmap_insert!(state, "loading", false);

                Vec::new()
            }
        };

        self.backup_model.borrow_mut().reset_data(existing_backups);
        self.state = state;
        self.state_changed();
        self.backup_model_changed();
    }

    // fn refresh(&self) {

    // }
    // TODO: find an O(1) solution
    fn does_backup_exist_for_udid(&self, udid: QString) -> bool {
        let mut found = false;
        for item in self.backup_model.borrow().iter() {
            if item.udid == udid {
                found = true;
                break;
            }
        }
        found
    }

    fn get_backup_info(&self, udid: QString, root: QString) {
        let q_thread = self.qt_thread().clone();
        RUNTIME.spawn(async move {
            let udid = udid.to_string();
            let res = get_info_for_backup(q_thread.clone(), udid.clone(), root.to_string()).await;
            q_thread.queue(move |manager| match res {
                Ok(json) => {
                    manager.backupInfoReady(QString::from(udid), true, QString::from(json));
                }
                Err(err) => {
                    error!("failed to get backup info for {udid}: {err}");
                    manager.backupInfoReady(
                        QString::from(udid),
                        false,
                        QString::from(err.to_string()),
                    );
                }
            });
        });
    }

    // this one doesn't require device to be connected
    fn get_backup_info_without_device(&self, udid: QString, root: QString) {
        let q_thread = self.qt_thread().clone();
        RUNTIME.spawn(async move {
            get_info_for_backup_without_device(q_thread, udid.to_string(), root.to_string()).await;
        });
    }

    fn start_backup(&mut self, root: QString, udid: QString) {
        let udid = udid.to_string();
        let root = root.to_string();
        let q_thread = self.qt_thread();
        let udid_for_task = udid.clone();
        let task = RUNTIME.spawn(async move {
            let finish_udid = udid.clone();
            let result = run_backup(q_thread.clone(), udid, root.clone()).await;
            let success = result.is_ok();
            q_thread.queue(move |manager| {
                manager.operationFinished(
                    QString::from("backup"),
                    QString::from(finish_udid),
                    success,
                );
                manager.busy = false;
                manager.busy_changed();
            });
        });
        if let Some(prev_task) = self.tasks.insert(udid_for_task, task) {
            // cancel if there was any prev task
            // running for the same udid
            prev_task.abort();
        }
        self.busy = true;
        self.busy_changed();
    }

    fn cancel_operation(&mut self, udid: String) -> bool {
        if let Some(task) = self.tasks.remove(&udid) {
            task.abort();
            self.busy = false;
            self.busy_changed();
            true
        } else {
            false
        }
    }

    fn start_restore(
        &mut self,
        root: QString,
        udid: QString,
        password: QString,
        reboot: bool,
        copy: bool,
        preserve_settings: bool,
        system_files: bool,
        remove_items_not_restored: bool,
    ) {
        let udid = udid.to_string();
        let udid_for_task = udid.clone();
        let root = root.to_string();
        let password = password.to_string();
        let q_thread = self.qt_thread();

        let task = RUNTIME.spawn(async move {
            let finish_udid = udid.clone();
            let result = run_restore(
                q_thread.clone(),
                udid,
                root.clone(),
                password,
                reboot,
                copy,
                preserve_settings,
                system_files,
                remove_items_not_restored,
            )
            .await;

            let success = result.is_ok();
            if let Err(err) = result {
                error!("restore failed for {finish_udid}: {err}");
            }
            q_thread.queue(move |manager| {
                manager.tasks.remove(&finish_udid);
                manager.operationFinished(
                    QString::from("restore"),
                    QString::from(finish_udid),
                    success,
                );
                manager.busy = false;
                manager.busy_changed();
            });
        });

        if let Some(prev_task) = self.tasks.insert(udid_for_task, task) {
            prev_task.abort();
        }
        self.busy = true;
        self.busy_changed();
    }


    fn get_backup_metadata(&self, udid: QString, root: QString) -> QVariantMap {
        let mut result_metadata = QVariantMap::default();
   

        match read_backup_metadata(udid, root) {
            Ok((was_passcode_set, is_encrypted)) => {
                qvariantmap_insert!(result_metadata, "WasPasscodeSet", was_passcode_set);
                qvariantmap_insert!(result_metadata, "IsEncrypted", is_encrypted);
                qvariantmap_insert!(result_metadata, "success", true);
            }
            Err(err) => {
                error!("failed to get backup metadata: {err}");
                qvariantmap_insert!(result_metadata, "success", false);
            }
        }
        result_metadata
    }

    // fn erase_device(&mut self, root: QString, udid: QString) {
    //     if self.is_busy("erase") {
    //         return;
    //     }

    //     let udid = udid.to_string();
    //     let root = root.to_string();
    //     let q_thread = self.qt_thread();
    //     self.set_state(
    //         true,
    //         "erase",
    //         0.0,
    //         "0%",
    //         "",
    //         "Sending erase command...",
    //         "",
    //         &root,
    //         &udid,
    //     );
    //     self.operationStarted(QString::from("erase"), QString::from(udid.clone()));

    //     let task = RUNTIME.spawn(async move {
    //         let finish_udid = udid.clone();
    //         let result = run_erase(udid, root.clone()).await;
    //         let success = result.is_ok();
    //         q_thread.queue(move |manager| {
    //             manager.active_task = None;
    //             match result {
    //                 Ok(()) => manager.set_state(
    //                     false,
    //                     "",
    //                     1.0,
    //                     "100%",
    //                     "",
    //                     "Erase command sent.",
    //                     "",
    //                     &root,
    //                     &finish_udid,
    //                 ),
    //                 Err(err) => manager.set_state(
    //                     false,
    //                     "",
    //                     0.0,
    //                     "0%",
    //                     "",
    //                     "Erase failed.",
    //                     &err.to_string(),
    //                     &root,
    //                     &finish_udid,
    //                 ),
    //             }
    //             manager.operationFinished(
    //                 QString::from("erase"),
    //                 QString::from(finish_udid),
    //                 success,
    //             );
    //         });
    //     });

    //     self.active_task = Some(task);
    // }

    // fn cancel(&mut self) {
    //     if let Some(task) = self.active_task.take() {
    //         task.abort();
    //         self.set_state(false, "", 0.0, "0%", "", "Operation cancelled.", "", "", "");
    //     }
    // }

    // fn is_busy(&mut self, operation: &str) -> bool {
    //     if self.active_task.is_some() {
    //         error!("backup manager refused {operation}: another operation is active");
    //         self.set_state(
    //             true,
    //             operation,
    //             0.0,
    //             "0%",
    //             "",
    //             "Another backup operation is already running.",
    //             "Wait for the current operation to finish or cancel it first.",
    //             "",
    //             "",
    //         );
    //         return true;
    //     }
    //     false
    // }

    // fn set_state(
    //     &mut self,
    //     busy: bool,
    //     operation: &str,
    //     progress: f64,
    //     percent_text: &str,
    //     time_remaining: &str,
    //     status_text: &str,
    //     error: &str,
    //     backup_root: &str,
    //     active_udid: &str,
    // ) {
    //     self.state = state_map(
    //         busy,
    //         operation,
    //         progress,
    //         percent_text,
    //         time_remaining,
    //         status_text,
    //         error,
    //         backup_root,
    //         active_udid,
    //     );
    //     self.state_changed();
    // }
}

// impl Drop for BackupManager {
//     fn drop(&mut self) {
//         if let Some(task) = self.active_task.take() {
//             task.abort();
//         }
//     }
// }

// impl From<BackupInfo> for BackupListItem {
//     fn from(info: BackupInfo) -> Self {
//         Self {
//             udid: QString::from(info.udid),
//             source: QString::from(info.source),
//             device_name: QString::from(info.device_name),
//             display_name: QString::from(info.display_name),
//             last_backup: QString::from(info.last_backup),
//             version: QString::from(info.version),
//             encrypted: info.encrypted,
//             path: QString::from(info.path),
//             status: QString::from(info.status),
//         }
//     }
// }


fn read_backup_metadata(udid: QString, root: QString) -> anyhow::Result<(bool, bool)> {
    let path = PathBuf::from(root.to_string()).join(udid.to_string()).join("Manifest.plist");

    let metadata = plist::Value::from_file(&path)?;
    let metadata = metadata.as_dictionary().ok_or_else(|| anyhow::anyhow!("Manifest.plist is not a dictionary"))?;

    let was_passcode_set = metadata.get("WasPasscodeSet").and_then(|v| v.as_boolean()).ok_or_else(|| anyhow::anyhow!("WasPasscodeSet is not a boolean"))?;
    let is_encrypted = metadata.get("IsEncrypted").and_then(|v| v.as_boolean()).ok_or_else(|| anyhow::anyhow!("IsEncrypted is not a boolean"))?;

    Ok((was_passcode_set, is_encrypted))
} 

#[derive(Clone)]
struct iDescriptorBackupDelegate {
    fs: FsBackupDelegate,
    qt_thread: QtThread<BackupManager>,
    operation: &'static str,
    root: String,
    udid: QString,
    start_time: Arc<Mutex<Option<Instant>>>,
}

impl iDescriptorBackupDelegate {
    fn new(
        qt_thread: QtThread<BackupManager>,
        operation: &'static str,
        root: String,
        udid: QString,
    ) -> Self {
        Self {
            fs: FsBackupDelegate,
            qt_thread,
            operation,
            root,
            udid,
            start_time: Arc::new(Mutex::new(None)),
        }
    }
}

impl BackupDelegate for iDescriptorBackupDelegate {
    fn get_free_disk_space(&self, path: &Path) -> u64 {
        self.fs.get_free_disk_space(path)
    }

    fn open_file_read<'a>(
        &'a self,
        path: &'a Path,
    ) -> Pin<Box<dyn Future<Output = Result<Box<dyn Read + Send>, IdeviceError>> + Send + 'a>> {
        self.fs.open_file_read(path)
    }

    fn create_file_write<'a>(
        &'a self,
        path: &'a Path,
    ) -> Pin<Box<dyn Future<Output = Result<Box<dyn Write + Send>, IdeviceError>> + Send + 'a>>
    {
        self.fs.create_file_write(path)
    }

    fn create_dir_all<'a>(
        &'a self,
        path: &'a Path,
    ) -> Pin<Box<dyn Future<Output = Result<(), IdeviceError>> + Send + 'a>> {
        self.fs.create_dir_all(path)
    }

    fn remove<'a>(
        &'a self,
        path: &'a Path,
    ) -> Pin<Box<dyn Future<Output = Result<(), IdeviceError>> + Send + 'a>> {
        self.fs.remove(path)
    }

    fn rename<'a>(
        &'a self,
        from: &'a Path,
        to: &'a Path,
    ) -> Pin<Box<dyn Future<Output = Result<(), IdeviceError>> + Send + 'a>> {
        self.fs.rename(from, to)
    }

    fn copy<'a>(
        &'a self,
        src: &'a Path,
        dst: &'a Path,
    ) -> Pin<Box<dyn Future<Output = Result<(), IdeviceError>> + Send + 'a>> {
        self.fs.copy(src, dst)
    }

    fn exists<'a>(&'a self, path: &'a Path) -> Pin<Box<dyn Future<Output = bool> + Send + 'a>> {
        self.fs.exists(path)
    }

    fn is_dir<'a>(&'a self, path: &'a Path) -> Pin<Box<dyn Future<Output = bool> + Send + 'a>> {
        self.fs.is_dir(path)
    }

    fn list_dir<'a>(
        &'a self,
        path: &'a Path,
    ) -> Pin<Box<dyn Future<Output = Result<Vec<DirEntryInfo>, IdeviceError>> + Send + 'a>> {
        self.fs.list_dir(path)
    }

    fn on_file_received(&self, path: &str, file_count: u32) {
        debug!("backup manager received file {file_count}: {path}");

        let udid = self.udid.clone();
        let path = QString::from(path.to_string());
        self.qt_thread.queue(move |manager| {
            manager.fileReceived(udid, path);
        });
    }

    fn on_progress(&self, bytes_done: u64, bytes_total: u64, overall_progress: f64) {
        let elapsed = {
            let mut start = self.start_time.lock().unwrap();
            let start = start.get_or_insert_with(Instant::now);
            start.elapsed()
        };

        let progress = if bytes_total > 0 {
            bytes_done as f64 / bytes_total as f64
        } else if overall_progress >= 0.0 {
            overall_progress / 100.0
        } else {
            0.0
        }
        .clamp(0.0, 1.0);

        // FIXME: It's way too inaccurate
        // let time_remaining = if progress > 0.0 && progress < 1.0 {
        //     let total = Duration::from_secs_f64(elapsed.as_secs_f64() / progress);
        //     Self::translated_time_remaining(total.saturating_sub(elapsed).as_secs())
        // } else {
        //     QString::default()
        // };

        let udid = self.udid.clone();
        self.qt_thread.queue(move |manager| {
            debug!("Progress: {}", progress);
            manager.progressUpdate(udid, progress);
        });
    }
}

async fn get_info_for_backup(
    qt_thread: QtThread<BackupManager>,
    udid: String,
    root: String,
) -> anyhow::Result<String> {
    println!("udid:{}, root:{}", udid, root);
    let device = crate::device_ctx::get_device(udid.clone()).await?;
    let provider_guard = device.provider.lock().await;
    let provider_ref: &dyn IdeviceProvider = provider_guard.as_ref();
    let mut client = MobileBackup2Client::connect(provider_ref).await?;
    drop(provider_guard);

    let delegate = iDescriptorBackupDelegate::new(qt_thread, "backup", root.clone(), udid.into());
    let dict = client
        .info_from_path(&PathBuf::from(root), None, &delegate)
        .await?;
    let value_dict = plist::Value::from(dict);
    let json = crate::utils::plist_value_to_json_string(&value_dict)?;
    // drop(provider_guard);

    // let response = client
    //     .backup_from_path(Path::new(&root), None, None, &delegate)
    //     .await?;
    // check_response(response)?;
    // let _ = client.disconnect().await;
    // info!("backup completed");
    Ok(json)
}

async fn get_info_for_backup_without_device(
    qt_thread: QtThread<BackupManager>,
    udid: String,
    root: String,
) {
    let signal_udid = udid.clone();
    let res: anyhow::Result<String> = async {
        let backup_path = PathBuf::from(root).join(&udid);
        let manifest_path = backup_path.join("Manifest.plist");
        let size_path = backup_path.clone();

        let bytes = tokio::fs::read(manifest_path).await?;
        let plist: plist::Value = plist::from_bytes(&bytes)?;
        let (folder_size, folder_files) = calculate_folder_size(size_path).await?;
        let mut value = serde_json::to_value(&plist)?;

        if let serde_json::Value::Object(ref mut obj) = value {
            obj.insert("FolderSize".into(), serde_json::json!(folder_size));
            obj.insert("FolderFiles".into(), serde_json::json!(folder_files));
        }

        Ok(serde_json::to_string(&value)?)
    }
    .await;

    qt_thread.queue(move |manager| match res {
        Ok(json) => {
            manager.backupInfoReadyWithoutDevice(
                QString::from(signal_udid),
                true,
                QString::from(json),
            );
        }
        Err(err) => {
            error!("failed to get backup info without device for {signal_udid}: {err}");
            manager.backupInfoReadyWithoutDevice(
                QString::from(signal_udid),
                false,
                QString::from(err.to_string()),
            );
        }
    });
}

async fn calculate_folder_size(path: PathBuf) -> anyhow::Result<(u64, u64)> {
    tokio::task::spawn_blocking(move || {
        let mut total_size = 0_u64;
        let mut total_files = 0_u64;
        let mut pending = vec![path];

        while let Some(dir) = pending.pop() {
            for entry in std::fs::read_dir(dir)? {
                let entry = entry?;
                let metadata = entry.metadata()?;

                if metadata.is_dir() {
                    pending.push(entry.path());
                } else if metadata.is_file() {
                    total_size = total_size.saturating_add(metadata.len());
                    total_files = total_files.saturating_add(1);
                }
            }
        }

        Ok((total_size, total_files))
    })
    .await?
}

async fn run_backup(
    qt_thread: QtThread<BackupManager>,
    udid: String,
    root: String,
) -> anyhow::Result<()> {
    let device = crate::device_ctx::get_device(udid.clone()).await?;
    let provider_guard = device.provider.lock().await;
    let provider_ref: &dyn IdeviceProvider = provider_guard.as_ref();
    let mut client = MobileBackup2Client::connect(provider_ref).await?;
    drop(provider_guard);

    let delegate = iDescriptorBackupDelegate::new(qt_thread, "backup", root.clone(), udid.into());
    let response = client
        .backup_from_path(Path::new(&root), None, None, &delegate)
        .await?;
    check_response(response)?;
    let _ = client.disconnect().await;
    info!("backup completed");
    Ok(())
}

#[allow(clippy::too_many_arguments)]
async fn run_restore(
    qt_thread: QtThread<BackupManager>,
    udid: String,
    root: String,
    password: String,
    reboot: bool,
    copy: bool,
    preserve_settings: bool,
    system_files: bool,
    remove_items_not_restored: bool,
) -> anyhow::Result<()> {
    let device = crate::device_ctx::get_device(udid.clone()).await?;
    let provider_guard = device.provider.lock().await;
    let provider_ref: &dyn IdeviceProvider = provider_guard.as_ref();
    let mut client = MobileBackup2Client::connect(provider_ref).await?;
    drop(provider_guard);

    let mut options = RestoreOptions::new()
        .with_reboot(reboot)
        .with_copy(copy)
        .with_preserve_settings(preserve_settings)
        .with_system_files(system_files)
        .with_remove_items_not_restored(remove_items_not_restored);
    if !password.is_empty() {
        options = options.with_password(password);
    }

    let delegate =
        iDescriptorBackupDelegate::new(qt_thread, "restore", root.clone(), QString::from(udid));
    let response = client
        .restore_from_path(Path::new(&root), None, Some(options), &delegate)
        .await?;
    check_response(response)?;
    let _ = client.disconnect().await;
    info!("restore completed");
    Ok(())
}

// async fn run_erase(udid: String, root: String) -> anyhow::Result<()> {
//     let device = crate::device_ctx::get_device(udid.clone()).await?;
//     let provider_guard = device.provider.lock().await;
//     let provider_ref: &dyn IdeviceProvider = provider_guard.as_ref();
//     let mut client = MobileBackup2Client::connect(provider_ref).await?;
//     drop(provider_guard);

//     let delegate = FsBackupDelegate;
//     client
//         .erase_device_from_path(Path::new(&root), &delegate)
//         .await?;
//     let _ = client.disconnect().await;
//     info!("erase command sent");
//     Ok(())
// }

fn check_response(response: Option<plist::Dictionary>) -> anyhow::Result<()> {
    if let Some(response) = response {
        if let Some(code) = response
            .get("ErrorCode")
            .and_then(|v| v.as_unsigned_integer())
        {
            if code != 0 {
                let desc = response
                    .get("ErrorDescription")
                    .and_then(|v| v.as_string())
                    .unwrap_or("Unknown error");
                anyhow::bail!("ErrorCode {code}: {desc}");
            }
        }
    }
    Ok(())
}

// async fn read_backup_info(path: PathBuf) -> Option<BackupInfo> {
//     let source = path.file_name()?.to_string_lossy().to_string();
//     let udid = source.clone();
//     let info_path = path.join("Info.plist");
//     let manifest_path = path.join("Manifest.plist");
//     let status_path = path.join("Status.plist");

//     if !tokio::fs::try_exists(&info_path).await.ok()?
//         || !tokio::fs::try_exists(&manifest_path).await.ok()?
//     {
//         return None;
//     }

//     let info = read_plist_dict(&info_path).await.unwrap_or_default();
//     let manifest = read_plist_dict(&manifest_path).await.unwrap_or_default();
//     let status = read_plist_dict(&status_path).await.unwrap_or_default();

//     let device_name = string_value(&info, "Device Name")
//         .or_else(|| string_value(&info, "DeviceName"))
//         .unwrap_or_else(|| "Unknown Device".to_string());
//     let display_name = string_value(&info, "Display Name")
//         .or_else(|| string_value(&info, "DisplayName"))
//         .unwrap_or_else(|| device_name.clone());
//     let version = string_value(&info, "Product Version")
//         .or_else(|| string_value(&info, "ProductVersion"))
//         .unwrap_or_default();
//     let encrypted = manifest
//         .get("IsEncrypted")
//         .and_then(|v| v.as_boolean())
//         .unwrap_or(false);
//     let status_text = string_value(&status, "Status").unwrap_or_else(|| "Available".to_string());
//     let last_backup = plist_date_string(&status)
//         .or_else(|| plist_date_string(&info))
//         .or_else(|| file_modified_string(&path))
//         .unwrap_or_default();

//     Some(BackupInfo {
//         udid,
//         source,
//         device_name,
//         display_name,
//         last_backup,
//         version,
//         encrypted,
//         path: path.to_string_lossy().to_string(),
//         status: status_text,
//     })
// }

// async fn read_plist_dict(path: &Path) -> Option<plist::Dictionary> {
//     let data = tokio::fs::read(path).await.ok()?;
//     match plist::from_bytes::<Value>(&data).ok()? {
//         Value::Dictionary(dict) => Some(dict),
//         _ => None,
//     }
// }

// fn string_value(dict: &plist::Dictionary, key: &str) -> Option<String> {
//     dict.get(key)
//         .and_then(|value| value.as_string())
//         .map(ToString::to_string)
// }

// fn plist_date_string(dict: &plist::Dictionary) -> Option<String> {
//     for key in ["Date", "Last Backup Date", "LastBackupDate", "SnapshotDate"] {
//         if let Some(value) = dict.get(key) {
//             if let Some(date) = value.as_date() {
//                 return Some(format!("{date:?}"));
//             }
//             if let Some(text) = value.as_string() {
//                 return Some(text.to_string());
//             }
//         }
//     }
//     None
// }

// fn file_modified_string(path: &Path) -> Option<String> {
//     let modified = std::fs::metadata(path).ok()?.modified().ok()?;
//     let duration = modified.duration_since(SystemTime::UNIX_EPOCH).ok()?;
//     Some(format!("{} seconds since epoch", duration.as_secs()))
// }

// fn state_map(
//     busy: bool,
//     operation: &str,
//     progress: f64,
//     percent_text: &str,
//     time_remaining: &str,
//     status_text: &str,
//     error: &str,
//     backup_root: &str,
//     active_udid: &str,
// ) -> QVariantMap {
//     let mut state = QVariantMap::default();
//     qvariantmap_insert!(state, "busy", busy);
//     qvariantmap_insert!(state, "operation", QString::from(operation));
//     qvariantmap_insert!(state, "progress", progress);
//     qvariantmap_insert!(state, "percentText", QString::from(percent_text));
//     qvariantmap_insert!(state, "timeRemaining", QString::from(time_remaining));
//     qvariantmap_insert!(state, "statusText", QString::from(status_text));
//     qvariantmap_insert!(state, "error", QString::from(error));
//     qvariantmap_insert!(state, "backupRoot", QString::from(backup_root));
//     qvariantmap_insert!(state, "activeUdid", QString::from(active_udid));
//     state
// }
