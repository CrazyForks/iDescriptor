use crate::{RUNTIME, qt_threading::QtThreading, qvariantmap_insert};
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::QVariantMap;
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
};

#[cfg(target_os = "linux")]
use tokio::process::Command;

#[cfg(target_os = "windows")]
use {
    once_cell::sync::Lazy,
    std::sync::Mutex,
    win_ifuse::{MountHandle, WinIfuseBuilder},
};

#[cfg(target_os = "windows")]
enum RegistryMount {
    Pending { udid: String },
    Mounted { udid: String, handle: MountHandle },
}

#[cfg(target_os = "windows")]
static MOUNTS: Lazy<Mutex<HashMap<String, RegistryMount>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

#[allow(non_snake_case)]
#[derive(QObject, Default, QtThreading)]
pub struct IFuse {
    base: qt_base_class!(trait QObject),
    state: qt_property!(QVariantMap; NOTIFY stateChanged),
    stateChanged: qt_signal!(),
    deviceStateChanged: qt_signal!(udid: QString),
    device_states: HashMap<String, QVariantMap>,
    state_for_device: qt_method!(fn(&self, udid: QString) -> QVariantMap),
    default_mount_path: qt_method!(fn(&self, product_type: QString) -> QString),
    mount: qt_method!(fn(&mut self, udid: QString, mount_path: QString)),
    unmount: qt_method!(fn(&mut self, mount_path: QString)),
    unmount_device: qt_method!(fn(&mut self, udid: QString)),
    unmount_device_path: qt_method!(fn(&mut self, udid: QString, mount_path: QString)),
}

impl IFuse {
    pub fn new_with_state() -> Self {
        let state = default_state();
        Self {
            state,
            ..Default::default()
        }
    }

    fn state_for_device(&self, udid: QString) -> QVariantMap {
        self.device_states
            .get(&udid.to_string())
            .cloned()
            .unwrap_or_else(default_state)
    }

    fn default_mount_path(&self, product_type: QString) -> QString {
        let product_type = product_type.to_string().replace(['/', '\\'], "-");
        let home = home_dir().unwrap_or_else(|| PathBuf::from("."));
        QString::from(home.join(product_type).to_string_lossy().to_string())
    }

    fn mount(&mut self, udid: QString, mount_path: QString) {
        let udid = udid.to_string();
        let mount_path = mount_path.to_string();
        if udid.trim().is_empty() {
            self.set_status("", "Error: No device selected", true, false, false, "");
            return;
        }
        if mount_path.trim().is_empty() {
            self.set_status(
                &udid,
                "Error: No mount path selected",
                true,
                false,
                false,
                "",
            );
            return;
        }

        #[cfg(target_os = "windows")]
        {
            if Path::new(&mount_path).exists() {
                self.set_status(
                    &udid,
                    &format!("Error: Mount path must not exist on Windows: {mount_path}"),
                    true,
                    false,
                    false,
                    "",
                );
                return;
            }
            if let Err(error) = reserve_windows_mount(&udid, &mount_path) {
                self.set_status(&udid, &error, true, false, false, "");
                return;
            }

            self.set_status(&udid, "Mounting device...", false, true, false, &mount_path);
            let q_thread = self.qt_thread();
            let state_udid = udid.clone();
            RUNTIME.spawn(async move {
                match WinIfuseBuilder::usb(udid.clone())
                    .mount_point(&mount_path)
                    .mount()
                    .await
                {
                    Ok(handle) => {
                        finish_windows_mount(&udid, &mount_path, handle);
                        q_thread.queue(move |q| {
                            q.set_status(
                                &state_udid,
                                &format!("Device mounted successfully at: {mount_path}"),
                                false,
                                false,
                                true,
                                &mount_path,
                            );
                        });
                    }
                    Err(error) => {
                        cancel_windows_reservation(&mount_path);
                        q_thread.queue(move |q| {
                            q.set_status(
                                &state_udid,
                                &format!("Mount failed: {error:#}"),
                                true,
                                false,
                                false,
                                "",
                            );
                        });
                    }
                }
            });
            return;
        }

        #[cfg(target_os = "linux")]
        {
            let ifuse_path = match ifuse_executable_path() {
                Ok(path) => path,
                Err(error) => {
                    self.set_status(&udid, &error, true, false, false, "");
                    return;
                }
            };
            if !Path::new(&mount_path).exists() {
                if let Err(error) = std::fs::create_dir_all(&mount_path) {
                    self.set_status(
                        &udid,
                        &format!("Error: Failed to create mount directory: {mount_path}: {error}"),
                        true,
                        false,
                        false,
                        "",
                    );
                    return;
                }
            }

            self.set_status(&udid, "Mounting device...", false, true, false, &mount_path);
            let q_thread = self.qt_thread();
            let state_udid = udid.clone();
            RUNTIME.spawn(async move {
                let output = Command::new(&ifuse_path)
                    .arg("-u")
                    .arg(&udid)
                    .arg(&mount_path)
                    .output()
                    .await;
                match output {
                    Ok(output) if output.status.success() => q_thread.queue(move |q| {
                        q.set_status(
                            &state_udid,
                            &format!("Device mounted successfully at: {mount_path}"),
                            false,
                            false,
                            true,
                            &mount_path,
                        );
                    }),
                    Ok(output) => {
                        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
                        let error = if stderr.is_empty() {
                            format!("Mount failed with exit code: {}", output.status)
                        } else {
                            format!("Mount failed: {stderr}")
                        };
                        q_thread.queue(move |q| {
                            q.set_status(&state_udid, &error, true, false, false, "")
                        });
                    }
                    Err(error) => {
                        let error = process_error_message(&error);
                        q_thread.queue(move |q| {
                            q.set_status(
                                &state_udid,
                                &format!("Error: {error}"),
                                true,
                                false,
                                false,
                                "",
                            )
                        });
                    }
                }
            });
        }
    }

    fn unmount(&mut self, mount_path: QString) {
        let mount_path = mount_path.to_string();
        if mount_path.trim().is_empty() {
            self.set_status("", "Error: No mount path selected", true, false, false, "");
            return;
        }
        #[cfg(target_os = "windows")]
        let udid = udid_for_mount_path(&mount_path).unwrap_or_default();
        #[cfg(not(target_os = "windows"))]
        let udid = String::new();
        self.begin_unmount(udid, mount_path);
    }

    fn unmount_device(&mut self, udid: QString) {
        let udid = udid.to_string();
        #[cfg(target_os = "windows")]
        {
            let paths = mounted_paths_for_udid(&udid);
            if let Some(path) = paths.into_iter().next() {
                self.begin_unmount(udid, path);
            }
        }
        #[cfg(not(target_os = "windows"))]
        let _ = udid;
    }

    fn unmount_device_path(&mut self, udid: QString, mount_path: QString) {
        let udid = udid.to_string();
        let mount_path = mount_path.to_string();
        if !mount_path.trim().is_empty() {
            self.begin_unmount(udid, mount_path);
        }
    }

    fn begin_unmount(&mut self, udid: String, mount_path: String) {
        self.set_status(
            &udid,
            "Unmounting device...",
            false,
            true,
            true,
            &mount_path,
        );
        let q_thread = self.qt_thread();
        RUNTIME.spawn(async move {
            match unmount_path(&mount_path).await {
                Ok(()) => q_thread.queue(move |q| {
                    q.set_status(
                        &udid,
                        &format!("Device unmounted from {mount_path}"),
                        false,
                        false,
                        false,
                        "",
                    );
                }),
                Err(error) => q_thread.queue(move |q| {
                    q.set_status(
                        &udid,
                        &format!("Failed to unmount iFuse at {mount_path}. {error}"),
                        true,
                        false,
                        true,
                        &mount_path,
                    );
                }),
            }
        });
    }

    fn set_status(
        &mut self,
        udid: &str,
        message: &str,
        is_error: bool,
        busy: bool,
        mounted: bool,
        mount_path: &str,
    ) {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "busy", busy);
        qvariantmap_insert!(state, "mounted", mounted);
        qvariantmap_insert!(state, "mountPath", QString::from(mount_path));
        qvariantmap_insert!(state, "message", QString::from(message));
        qvariantmap_insert!(state, "isError", is_error);
        self.device_states.insert(udid.to_string(), state.clone());
        self.state = state;
        self.stateChanged();
        self.deviceStateChanged(QString::from(udid));
    }
}

fn default_state() -> QVariantMap {
    let mut state = QVariantMap::default();
    qvariantmap_insert!(state, "busy", false);
    qvariantmap_insert!(state, "mounted", false);
    qvariantmap_insert!(state, "mountPath", QString::default());
    qvariantmap_insert!(state, "message", QString::default());
    qvariantmap_insert!(state, "isError", false);
    state
}

#[cfg(target_os = "windows")]
fn normalize_mount_path(path: &str) -> String {
    let absolute = std::path::absolute(path).unwrap_or_else(|_| PathBuf::from(path));
    let normalized = absolute.to_string_lossy().replace('/', "\\");
    normalized
        .strip_prefix(r"\\?\")
        .unwrap_or(&normalized)
        .trim_end_matches('\\')
        .to_lowercase()
}

#[cfg(target_os = "windows")]
fn reserve_windows_mount(udid: &str, mount_path: &str) -> Result<(), String> {
    let key = normalize_mount_path(mount_path);
    let mut mounts = MOUNTS.lock().unwrap();
    if mounts.contains_key(&key) {
        return Err(format!("Error: Mount path is already in use: {mount_path}"));
    }
    if mounts.values().any(|entry| match entry {
        RegistryMount::Pending { udid: existing }
        | RegistryMount::Mounted { udid: existing, .. } => existing == udid,
    }) {
        return Err("Error: This device already has an iDescriptor media mount".into());
    }
    mounts.insert(key, RegistryMount::Pending { udid: udid.into() });
    Ok(())
}

#[cfg(target_os = "windows")]
fn finish_windows_mount(udid: &str, mount_path: &str, handle: MountHandle) {
    MOUNTS.lock().unwrap().insert(
        normalize_mount_path(mount_path),
        RegistryMount::Mounted {
            udid: udid.into(),
            handle,
        },
    );
}

#[cfg(target_os = "windows")]
fn cancel_windows_reservation(mount_path: &str) {
    MOUNTS
        .lock()
        .unwrap()
        .remove(&normalize_mount_path(mount_path));
}

#[cfg(target_os = "windows")]
pub(crate) fn mounted_paths() -> Vec<String> {
    let mut paths = MOUNTS
        .lock()
        .unwrap()
        .values()
        .filter_map(|entry| match entry {
            RegistryMount::Mounted { handle, .. } => {
                Some(handle.mount_point().to_string_lossy().into_owned())
            }
            RegistryMount::Pending { .. } => None,
        })
        .collect::<Vec<_>>();
    paths.sort();
    paths
}

#[cfg(target_os = "windows")]
fn mounted_paths_for_udid(udid: &str) -> Vec<String> {
    MOUNTS
        .lock()
        .unwrap()
        .values()
        .filter_map(|entry| match entry {
            RegistryMount::Mounted {
                udid: mounted_udid,
                handle,
            } if mounted_udid == udid => Some(handle.mount_point().to_string_lossy().into_owned()),
            _ => None,
        })
        .collect()
}

#[cfg(target_os = "windows")]
fn udid_for_mount_path(mount_path: &str) -> Option<String> {
    MOUNTS
        .lock()
        .unwrap()
        .get(&normalize_mount_path(mount_path))
        .map(|entry| match entry {
            RegistryMount::Pending { udid } | RegistryMount::Mounted { udid, .. } => udid.clone(),
        })
}

#[cfg(target_os = "windows")]
pub(crate) async fn unmount_path(mount_path: &str) -> Result<(), String> {
    let entry = MOUNTS
        .lock()
        .unwrap()
        .remove(&normalize_mount_path(mount_path));
    match entry {
        Some(RegistryMount::Mounted { handle, .. }) => {
            handle.unmount().await.map_err(|error| format!("{error:#}"))
        }
        Some(RegistryMount::Pending { .. }) => Err("Mount is still starting".into()),
        None => Err("Mount is not managed by iDescriptor".into()),
    }
}

#[cfg(target_os = "windows")]
pub(crate) fn shutdown_all_mounts() {
    let handles = {
        let mut mounts = MOUNTS.lock().unwrap();
        mounts
            .drain()
            .filter_map(|(_, entry)| match entry {
                RegistryMount::Mounted { handle, .. } => Some(handle),
                RegistryMount::Pending { .. } => None,
            })
            .collect::<Vec<_>>()
    };
    RUNTIME.block_on(async {
        for handle in handles {
            if let Err(error) = handle.unmount().await {
                log::warn!(
                    "failed to unmount {} during shutdown: {error:#}",
                    handle.mount_point().display()
                );
            }
        }
    });
}

#[cfg(target_os = "linux")]
fn ifuse_executable_path() -> Result<PathBuf, String> {
    if let Some(path) = std::env::var_os("IFUSE_BIN_APPIMAGE").map(PathBuf::from) {
        if is_executable(&path) {
            return Ok(path);
        }
        return Err("Error: ifuse not found or is not executable.".into());
    }
    find_executable("ifuse")
        .ok_or_else(|| "Error: ifuse binary not found. Please install ifuse first.".into())
}

#[cfg(target_os = "linux")]
pub(crate) async fn unmount_path(mount_path: &str) -> Result<(), String> {
    let unmount_bin = find_executable("fusermount")
        .or_else(|| find_executable("fusermount3"))
        .or_else(|| find_executable("umount"))
        .ok_or_else(|| "No unmount helper found.".to_string())?;
    let mut command = Command::new(&unmount_bin);
    if unmount_bin
        .file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| name.starts_with("fusermount"))
    {
        command.arg("-u");
    }
    let output = command
        .arg(mount_path)
        .output()
        .await
        .map_err(|error| error.to_string())?;
    if output.status.success() {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
    }
}

fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(PathBuf::from)
}

#[cfg(target_os = "linux")]
fn find_executable(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths)
            .map(|directory| directory.join(name))
            .find(|candidate| is_executable(candidate))
    })
}

#[cfg(target_os = "linux")]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.is_file()
        && std::fs::metadata(path)
            .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
}

#[cfg(target_os = "linux")]
fn process_error_message(error: &std::io::Error) -> String {
    match error.kind() {
        std::io::ErrorKind::NotFound => "Failed to start ifuse. Make sure it's installed.".into(),
        std::io::ErrorKind::TimedOut => "ifuse process timed out.".into(),
        _ => format!("Unknown error occurred. {error}"),
    }
}

#[cfg(all(test, target_os = "windows"))]
mod tests {
    use super::normalize_mount_path;

    #[test]
    fn normalizes_windows_mount_keys() {
        assert_eq!(
            normalize_mount_path(r"C:\Mount\\"),
            normalize_mount_path("c:/mount")
        );
    }
}
