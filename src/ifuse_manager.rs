use crate::RUNTIME;
use crate::ifuse::unmount_path;
use crate::qt_threading::QtThreading;
use log::{debug, warn};
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::QStringList;
use std::sync::Arc;
use tokio::sync::Mutex;

#[allow(non_snake_case)]
#[derive(QObject, Default, QtThreading)]
pub struct IFuseManager {
    base: qt_base_class!(trait QObject),
    mountPoints: qt_property!(QStringList; NOTIFY mountPointsChanged),
    mountPointsChanged: qt_signal!(),
    busyPath: qt_property!(QString; NOTIFY busyPathChanged),
    busyPathChanged: qt_signal!(),
    refresh: qt_method!(fn(&self)),
    unmount: qt_method!(fn(&mut self, mount_path: QString)),
    unmountFinished: qt_signal!(mount_path: QString, success: bool, error: QString),
    operation_lock: Arc<Mutex<()>>,
}

impl IFuseManager {
    fn refresh(&self) {
        let qt_thread = self.qt_thread();
        let operation_lock = self.operation_lock.clone();

        RUNTIME.spawn(async move {
            let _operation_guard = operation_lock.lock().await;
            match discover_mount_points().await {
                Ok(mount_points) => {
                    qt_thread.queue(move |manager| {
                        manager.mountPoints = to_qstring_list(mount_points);
                        manager.mountPointsChanged();
                    });
                }
                Err(error) => {
                    warn!("Failed to discover iFuse mount points: {error}");
                }
            }
        });
    }

    fn unmount(&mut self, mount_path: QString) {
        if mount_path.is_empty() || !self.busyPath.is_empty() {
            return;
        }

        self.busyPath = mount_path.clone();
        self.busyPathChanged();

        let mount_path_string = mount_path.to_string();
        let qt_thread = self.qt_thread();
        let operation_lock = self.operation_lock.clone();

        RUNTIME.spawn(async move {
            let _operation_guard = operation_lock.lock().await;
            let result = unmount_path(&mount_path_string).await;
            let refreshed_mount_points = discover_mount_points().await;

            qt_thread.queue(move |manager| {
                manager.busyPath = QString::default();
                manager.busyPathChanged();

                match refreshed_mount_points {
                    Ok(mount_points) => {
                        manager.mountPoints = to_qstring_list(mount_points);
                        manager.mountPointsChanged();
                    }
                    Err(error) => {
                        warn!("Failed to refresh iFuse mount points after unmount: {error}");
                        if result.is_ok() {
                            manager.mountPoints =
                                without_path(&manager.mountPoints, &mount_path_string);
                            manager.mountPointsChanged();
                        }
                    }
                }

                match result {
                    Ok(()) => {
                        debug!("Successfully unmounted iFuse at {mount_path_string}");
                        manager.unmountFinished(
                            QString::from(mount_path_string),
                            true,
                            QString::default(),
                        );
                    }
                    Err(error) => {
                        warn!("Failed to unmount iFuse at {mount_path_string}: {error}");
                        manager.unmountFinished(
                            QString::from(mount_path_string),
                            false,
                            QString::from(error),
                        );
                    }
                }
            });
        });
    }
}

async fn discover_mount_points() -> Result<Vec<String>, String> {
    #[cfg(target_os = "windows")]
    {
        return Ok(crate::ifuse::mounted_paths());
    }

    #[cfg(target_os = "linux")]
    {
        let mount_points = crate::ifuse::mounted_paths();
        // TODO(flatpak): This intentionally reads the sandbox mount namespace. Host-side iFuse
        // mounts preserved from an earlier Flatpak session are therefore not listed here. They
        // remain visible and unmountable through the user's host file manager; add host-side
        // discovery only if cross-session management becomes necessary.
        let mount_info = tokio::fs::read_to_string("/proc/self/mountinfo")
            .await
            .map_err(|error| format!("Failed to read /proc/self/mountinfo: {error}"))?;
        Ok(merge_mount_points(mount_points, &mount_info))
    }
}

#[cfg(target_os = "linux")]
fn merge_mount_points(mount_points: Vec<String>, mount_info: &str) -> Vec<String> {
    let mut mount_points = mount_points
        .into_iter()
        .map(|path| normalize_flatpak_mount_path(&path))
        .collect::<Vec<_>>();
    mount_points.extend(
        mount_info
            .lines()
            .filter_map(parse_mount_info_line)
            .map(|path| normalize_flatpak_mount_path(&path)),
    );
    mount_points.sort();
    mount_points.dedup();
    mount_points
}

// if we don't do this we may endup with duplicate mount points
// like the below
// -------------
// /home/uncore/.var/app/com.idescriptor.idescriptor/data/iDescriptor/iDescriptor/mounts/iPhone 11
// var/data/iDescriptor/iDescriptor/mounts/iPhone 11
// -------------
//
// they point to the same device but are treated as separate mount points
#[cfg(all(target_os = "linux", feature = "flatpak"))]
fn normalize_flatpak_mount_path(path: &str) -> String {
    let Some(host_data_root) = std::env::var_os("XDG_DATA_HOME") else {
        return path.to_string();
    };
    map_flatpak_data_path(path, std::path::Path::new(&host_data_root))
}

#[cfg(all(target_os = "linux", feature = "flatpak"))]
fn map_flatpak_data_path(path: &str, host_data_root: &std::path::Path) -> String {
    let path = std::path::Path::new(path);
    let Ok(relative_path) = path.strip_prefix("/var/data") else {
        return path.to_string_lossy().into_owned();
    };

    host_data_root
        .join(relative_path)
        .to_string_lossy()
        .into_owned()
}

#[cfg(all(target_os = "linux", not(feature = "flatpak")))]
fn normalize_flatpak_mount_path(path: &str) -> String {
    path.to_string()
}

#[cfg(target_os = "linux")]
fn parse_mount_info_line(line: &str) -> Option<String> {
    let (mount_fields, filesystem_fields) = line.split_once(" - ")?;
    let filesystem_type = filesystem_fields.split_whitespace().next()?;
    if !matches!(filesystem_type, "fuse.ifuse" | "fuse.ifuse-rs") {
        return None;
    }

    let mount_path = mount_fields.split_whitespace().nth(4)?;
    (!mount_path.is_empty()).then(|| decode_mount_info_path(mount_path))
}

#[cfg(target_os = "linux")]
fn decode_mount_info_path(path: &str) -> String {
    path.replace("\\040", " ")
        .replace("\\011", "\t")
        .replace("\\012", "\n")
        .replace("\\134", "\\")
}

fn to_qstring_list(paths: Vec<String>) -> QStringList {
    let mut result = QStringList::default();
    for path in paths {
        result.push(QString::from(path));
    }
    result
}

fn without_path(paths: &QStringList, excluded_path: &str) -> QStringList {
    let mut result = QStringList::default();
    for path in paths {
        if path.to_string() != excluded_path {
            result.push(path.clone());
        }
    }
    result
}

#[cfg(test)]
mod tests {
    #[cfg(target_os = "linux")]
    use super::{merge_mount_points, parse_mount_info_line};

    #[cfg(target_os = "linux")]
    #[test]
    fn parses_ifuse_mount_info() {
        assert_eq!(
            parse_mount_info_line(
                "119 95 0:68 / /home/user/iPhone\\0407 rw,nosuid,nodev - fuse.ifuse ifuse rw"
            ),
            Some("/home/user/iPhone 7".to_string())
        );
        assert_eq!(
            parse_mount_info_line(
                "120 95 0:69 / /run/user/1000/mounts/phone rw - fuse.ifuse-rs ifuse-rs rw"
            ),
            Some("/run/user/1000/mounts/phone".to_string())
        );
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn decodes_mount_info_escapes() {
        assert_eq!(
            parse_mount_info_line(
                "121 95 0:70 / /tmp/tab\\011line\\012slash\\134name rw - fuse.ifuse ifuse rw"
            ),
            Some("/tmp/tab\tline\nslash\\name".to_string())
        );
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn ignores_unrecognized_mount_info() {
        assert_eq!(parse_mount_info_line("not a mount line"), None);
        assert_eq!(
            parse_mount_info_line("119 95 8:1 / /mnt rw - ext4 /dev/sda1 rw"),
            None
        );
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn merges_registered_and_discovered_mounts_without_duplicates() {
        let mount_info = "119 95 0:68 / /tmp/iPhone\\0407 rw - fuse.ifuse-rs ifuse-rs rw";
        assert_eq!(
            merge_mount_points(vec!["/tmp/iPhone 7".into()], mount_info),
            vec!["/tmp/iPhone 7".to_string()]
        );
    }

    #[cfg(all(target_os = "linux", feature = "flatpak"))]
    #[test]
    fn maps_flatpak_data_alias_to_host_visible_path() {
        assert_eq!(
            super::map_flatpak_data_path(
                "/var/data/iDescriptor/iDescriptor/mounts/iPhone 7",
                std::path::Path::new("/home/user/.var/app/com.idescriptor.idescriptor/data")
            ),
            "/home/user/.var/app/com.idescriptor.idescriptor/data/iDescriptor/iDescriptor/mounts/iPhone 7"
        );
    }
}
