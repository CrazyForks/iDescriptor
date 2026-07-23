use crate::RUNTIME;
use crate::ifuse::unmount_path;
use crate::qt_threading::QtThreading;
use log::{debug, warn};
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::QStringList;
use std::sync::Arc;
use std::time::Duration;
use tokio::process::Command;
use tokio::sync::Mutex;

const COMMAND_TIMEOUT: Duration = Duration::from_secs(10);

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
    let output = tokio::time::timeout(
        COMMAND_TIMEOUT,
        Command::new("mount").args(["-t", "fuse.ifuse"]).output(),
    )
    .await
    .map_err(|_| "Timed out while discovering iFuse mount points".to_string())?
    .map_err(|error| format!("Failed to run mount: {error}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(if stderr.is_empty() {
            format!("mount exited with status {}", output.status)
        } else {
            stderr
        });
    }

    let output = String::from_utf8_lossy(&output.stdout);
    let mut mount_points = output
        .lines()
        .filter_map(parse_mount_point)
        .collect::<Vec<_>>();
    mount_points.sort();
    mount_points.dedup();
    Ok(mount_points)
}

fn parse_mount_point(line: &str) -> Option<String> {
    let (_, remainder) = line.split_once(" on ")?;
    let (mount_path, _) = remainder.split_once(" type ")?;
    let mount_path = mount_path.trim();
    (!mount_path.is_empty()).then(|| mount_path.to_string())
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
    use super::parse_mount_point;

    #[test]
    fn parses_ifuse_mount_output() {
        assert_eq!(
            parse_mount_point(
                "ifuse on /home/user/iPhone type fuse.ifuse (rw,nosuid,nodev,relatime)"
            ),
            Some("/home/user/iPhone".to_string())
        );
    }

    #[test]
    fn ignores_unrecognized_mount_output() {
        assert_eq!(parse_mount_point("not a mount line"), None);
    }
}
