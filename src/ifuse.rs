use crate::{RUNTIME, qt_threading::QtThreading, qvariantmap_insert};
use macros::QtThreading;
use qmetaobject::prelude::*;
use qttypes::QVariantMap;
use std::path::{Path, PathBuf};
use tokio::process::Command;

#[derive(QObject, Default, QtThreading)]
pub struct IFuse {
    base: qt_base_class!(trait QObject),
    state: qt_property!(QVariantMap; NOTIFY state_changed),
    state_changed: qt_signal!(),
    default_mount_path: qt_method!(fn(&self, product_type: QString) -> QString),
    mount: qt_method!(fn(&mut self, udid: QString, mount_path: QString)),
    unmount: qt_method!(fn(&mut self, mount_path: QString)),
}

impl IFuse {
    pub fn new_with_state() -> Self {
        let mut state = QVariantMap::default();
        qvariantmap_insert!(state, "busy", false);
        qvariantmap_insert!(state, "mounted", false);
        qvariantmap_insert!(state, "mountPath", QString::default());
        qvariantmap_insert!(state, "message", QString::default());
        qvariantmap_insert!(state, "isError", false);

        let mut def = Self::default();
        def.state = state;
        def
    }

    fn default_mount_path(&self, product_type: QString) -> QString {
        let product_type = product_type.to_string().replace(['/', '\\'], "-");
        let home = home_dir().unwrap_or_else(|| PathBuf::from("."));
        QString::from(home.join(product_type).to_string_lossy().to_string())
    }

    fn mount(&mut self, udid: QString, mount_path: QString) {
        let udid = udid.to_string();
        let mount_path = mount_path.to_string();

        if udid.is_empty() {
            self.set_status("Error: No device selected", true, false, false, "");
            return;
        }

        let ifuse_path = match ifuse_executable_path() {
            Ok(path) => path,
            Err(err) => {
                self.set_status(&err, true, false, false, "");
                return;
            }
        };

        #[cfg(target_os = "windows")]
        {
            // On Windows, the mount path must not exist.
            if Path::new(&mount_path).exists() {
                self.set_status(
                    &format!("Error: Mount directory must not exist on Windows: {mount_path}"),
                    true,
                    false,
                    false,
                    "",
                );
                return;
            }
        }

        #[cfg(target_os = "linux")]
        {
            // on Linux, we need to create the mount directory if it doesn't exist
            if !Path::new(&mount_path).exists() {
                if let Err(err) = std::fs::create_dir_all(&mount_path) {
                    self.set_status(
                        &format!("Error: Failed to create mount directory: {mount_path}: {err}"),
                        true,
                        false,
                        false,
                        "",
                    );
                    return;
                }
            }
        }

        self.set_status("Mounting device...", false, true, false, &mount_path);

        let q_thread = self.qt_thread();
        RUNTIME.spawn(async move {
            let output = Command::new(&ifuse_path)
                .arg("-u")
                .arg(&udid)
                .arg(&mount_path)
                .output()
                .await;

            match output {
                Ok(output) if output.status.success() => {
                    q_thread.queue(move |q| {
                        q.set_status(
                            &format!("Device mounted successfully at: {mount_path}"),
                            false,
                            false,
                            true,
                            &mount_path,
                        );
                    });
                }
                Ok(output) => {
                    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
                    let error = if stderr.is_empty() {
                        format!("Mount failed with exit code: {}", output.status)
                    } else {
                        format!("Mount failed: {stderr}")
                    };
                    q_thread.queue(move |q| {
                        q.set_status(&error, true, false, false, "");
                    });
                }
                Err(err) => {
                    let error = process_error_message(&err);
                    q_thread.queue(move |q| {
                        q.set_status(&format!("Error: {error}"), true, false, false, "");
                    });
                }
            }
        });
    }

    fn unmount(&mut self, mount_path: QString) {
        let mount_path = mount_path.to_string();
        if mount_path.is_empty() {
            self.set_status("Error: No mount path selected", true, false, false, "");
            return;
        }

        self.set_status("Unmounting device...", false, true, true, &mount_path);
        let q_thread = self.qt_thread();

        RUNTIME.spawn(async move {
            let result = unmount_path(&mount_path).await;
            match result {
                Ok(()) => {
                    q_thread.queue(move |q| {
                        q.set_status(
                            &format!("Device unmounted from {mount_path}"),
                            false,
                            false,
                            false,
                            "",
                        );
                    });
                }
                Err(err) => {
                    q_thread.queue(move |q| {
                        q.set_status(
                            &format!(
                                "Failed to unmount iFuse at {mount_path}. Please try again. {err}"
                            ),
                            true,
                            false,
                            true,
                            &mount_path,
                        );
                    });
                }
            }
        });
    }

    fn set_status(
        &mut self,
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

        self.state = state;
        self.state_changed();
    }
}

fn ifuse_executable_path() -> Result<PathBuf, String> {
    #[cfg(target_os = "windows")]
    {
        // On Windows we ship with a bundled win-ifuse.exe
        let exe = std::env::current_exe()
            .ok()
            .and_then(|path| path.parent().map(|parent| parent.join("win-ifuse.exe")))
            .ok_or_else(|| "Error: Could not resolve application directory.".to_string())?;

        println!("Looking for bundled win-ifuse.exe at {}", exe.display());
        if !exe.exists() {
            return Err(format!(
                "Error: win-ifuse.exe not found at expected path: {}",
                exe.display()
            ));
        }
        return Ok(exe);
    }

    #[cfg(target_os = "linux")]
    {
        /*
            Check if running in AppImage
            this is set by the plugin script
        */
        if std::env::var_os("IFUSE_BIN_APPIMAGE").is_some() {
            let path = std::env::var_os("IFUSE_BIN_APPIMAGE")
                .map(PathBuf::from)
                .filter(|path| !path.as_os_str().is_empty())
                .ok_or_else(|| {
                    "Error: Running in AppImage mode, but IFUSE_BIN_APPIMAGE is not set."
                        .to_string()
                })?;

            if !is_executable(&path) {
                return Err("Error: ifuse not found or is not executable.".to_string());
            }
            return Ok(path);
        }

        find_executable("ifuse")
            .ok_or_else(|| "Error: ifuse binary not found. Please install ifuse first.".to_string())
    }

    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    {
        Err("Error: iFuse is not supported on this platform.".to_string())
    }
}

#[cfg(target_os = "linux")]
async fn unmount_path(mount_path: &str) -> Result<(), String> {
    let unmount_bin = find_executable("fusermount")
        .or_else(|| find_executable("fusermount3"))
        .or_else(|| find_executable("umount"))
        .ok_or_else(|| "No unmount helper found.".to_string())?;

    let mut command = Command::new(&unmount_bin);
    if unmount_bin
        .file_name()
        .and_then(|name| name.to_str())
        .map(|name| name.starts_with("fusermount"))
        .unwrap_or(false)
    {
        command.arg("-u");
    }
    command.arg(mount_path);

    let output = command.output().await.map_err(|err| err.to_string())?;
    if output.status.success() {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
    }
}

#[cfg(target_os = "windows")]
async fn unmount_path(_mount_path: &str) -> Result<(), String> {
    // FIXME: implement Windows unmount parity with iFuseDiskUnmountButton/process kill.
    Err("Windows unmount is not implemented yet.".to_string())
}

fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(PathBuf::from)
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
fn find_executable(name: &str) -> Option<PathBuf> {
    let paths = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&paths) {
        let candidate = dir.join(name);
        if is_executable(&candidate) {
            return Some(candidate);
        }

        #[cfg(target_os = "windows")]
        {
            let candidate = dir.join(format!("{name}.exe"));
            if is_executable(&candidate) {
                return Some(candidate);
            }
        }
    }
    None
}

fn is_executable(path: &Path) -> bool {
    if !path.is_file() {
        return false;
    }

    #[cfg(target_os = "linux")]
    {
        use std::os::unix::fs::PermissionsExt;
        return std::fs::metadata(path)
            .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
            .unwrap_or(false);
    }

    #[cfg(not(target_os = "linux"))]
    {
        true
    }
}

fn process_error_message(err: &std::io::Error) -> String {
    match err.kind() {
        std::io::ErrorKind::NotFound => "Failed to start ifuse. Make sure it's installed.".into(),
        std::io::ErrorKind::TimedOut => "ifuse process timed out.".into(),
        _ => format!("Unknown error occurred. {err}"),
    }
}
