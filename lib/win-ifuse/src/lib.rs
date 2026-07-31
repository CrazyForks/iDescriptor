//! Embedded iOS AFC filesystem mounts for Windows.

#![cfg_attr(not(target_os = "windows"), allow(dead_code))]

#[cfg(target_os = "windows")]
mod afc;
#[cfg(target_os = "windows")]
mod filesystem;

use std::{
    net::IpAddr,
    path::{Path, PathBuf},
};

use anyhow::{Context, anyhow, bail};
use idevice::{
    IdeviceService,
    afc::AfcClient,
    pairing_file::PairingFile,
    provider::{IdeviceProvider, TcpProvider},
    services::house_arrest::HouseArrestClient,
    usbmuxd::{Connection, UsbmuxdAddr},
};

#[cfg(target_os = "windows")]
use std::sync::{Arc, Mutex};
#[cfg(target_os = "windows")]
use winfsp::host::{CoarseGuard, FileSystemHost, VolumeParams};

/// The device connection used by a mount.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DeviceTarget {
    Usb {
        udid: String,
    },
    Network {
        address: String,
        pairing_file: PathBuf,
    },
}

impl DeviceTarget {
    /// A stable identity suitable for mount registries and logs.
    pub fn identity(&self) -> String {
        match self {
            Self::Usb { udid } => format!("usb:{udid}"),
            Self::Network { address, .. } => format!("network:{address}"),
        }
    }
}

/// The AFC service exposed through the mount.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub enum MountSource {
    #[default]
    Media,
    Root,
    Documents {
        bundle_id: String,
    },
    Container {
        bundle_id: String,
    },
}

/// Configures and starts an embedded WinFsp mount.
#[derive(Clone, Debug)]
pub struct WinIfuseBuilder {
    target: DeviceTarget,
    mount_point: Option<PathBuf>,
    source: MountSource,
    volume_label: Option<String>,
}

impl WinIfuseBuilder {
    pub fn usb(udid: impl Into<String>) -> Self {
        Self {
            target: DeviceTarget::Usb { udid: udid.into() },
            mount_point: None,
            source: MountSource::default(),
            volume_label: None,
        }
    }

    pub fn network(address: impl Into<String>, pairing_file: impl Into<PathBuf>) -> Self {
        Self {
            target: DeviceTarget::Network {
                address: address.into(),
                pairing_file: pairing_file.into(),
            },
            mount_point: None,
            source: MountSource::default(),
            volume_label: None,
        }
    }

    pub fn mount_point(mut self, path: impl Into<PathBuf>) -> Self {
        self.mount_point = Some(path.into());
        self
    }

    pub fn source(mut self, source: MountSource) -> Self {
        self.source = source;
        self
    }

    pub fn volume_label(mut self, label: impl Into<String>) -> Self {
        self.volume_label = Some(label.into());
        self
    }

    fn validate(&self) -> anyhow::Result<&Path> {
        match &self.target {
            DeviceTarget::Usb { udid } if udid.trim().is_empty() => {
                bail!("USB UDID cannot be empty")
            }
            DeviceTarget::Network {
                address,
                pairing_file,
            } => {
                parse_network_address(address)?;
                if pairing_file.as_os_str().is_empty() {
                    bail!("network pairing file path cannot be empty");
                }
            }
            _ => {}
        }
        match &self.source {
            MountSource::Documents { bundle_id } | MountSource::Container { bundle_id }
                if bundle_id.trim().is_empty() =>
            {
                bail!("bundle ID cannot be empty")
            }
            _ => {}
        }
        if self
            .volume_label
            .as_ref()
            .is_some_and(|label| label.trim().is_empty())
        {
            bail!("volume label cannot be empty");
        }
        let mount_point = self
            .mount_point
            .as_deref()
            .ok_or_else(|| anyhow!("mount point is required"))?;
        if mount_point.as_os_str().is_empty() {
            bail!("mount point cannot be empty");
        }
        Ok(mount_point)
    }

    /// Connect to the device and start the WinFsp dispatcher.
    #[cfg(target_os = "windows")]
    pub async fn mount(self) -> anyhow::Result<MountHandle> {
        let mount_point = self.validate()?.to_path_buf();
        let runtime = tokio::runtime::Handle::try_current()
            .context("WinIfuseBuilder::mount must run inside a Tokio runtime")?;

        let client = match &self.target {
            DeviceTarget::Usb { udid } => {
                let address = UsbmuxdAddr::from_env_var().context("invalid usbmuxd address")?;
                let mut usbmuxd = address
                    .clone()
                    .connect(1)
                    .await
                    .context("connect to usbmuxd")?;
                let device = usbmuxd
                    .get_device(udid)
                    .await
                    .context("find USB device by UDID")?;
                if device.connection_type != Connection::Usb {
                    bail!("device {udid} is not connected over USB");
                }
                let provider = device.to_provider(address, "win-ifuse");
                connect_source(&provider, &self.source).await?
            }
            DeviceTarget::Network {
                address,
                pairing_file,
            } => {
                let (addr, scope_id) = parse_network_address(address)?;
                let provider = TcpProvider {
                    addr,
                    scope_id,
                    pairing_file: PairingFile::read_from_file(pairing_file)
                        .with_context(|| format!("read pairing file {}", pairing_file.display()))?,
                    label: "win-ifuse".into(),
                };
                connect_source(&provider, &self.source).await?
            }
        };

        let mut session = afc::AfcSession::new(client);
        let device_info = session
            .get_device_info()
            .await
            .context("read AFC volume information")?;
        let label = self.volume_label.clone().unwrap_or_else(|| {
            if device_info.model.is_empty() {
                "iPhone".into()
            } else {
                device_info.model
            }
        });

        let filesystem = filesystem::IfuseFilesystem::new(runtime, session, label);
        let mut params = VolumeParams::new();
        params
            .filesystem_name("win-ifuse")
            .sector_size(4096)
            .sectors_per_allocation_unit(1)
            .max_component_length(255)
            .case_sensitive_search(true)
            .case_preserved_names(true)
            .unicode_on_disk(true)
            .reparse_points(true)
            .no_reparse_points_dir_check(true)
            .persistent_acls(false);

        let mut host = FileSystemHost::<_, CoarseGuard>::new(params, filesystem)
            .context("create WinFsp filesystem")?;
        host.mount(&mount_point)
            .with_context(|| format!("mount at {}", mount_point.display()))?;
        if let Err(error) = host.start() {
            host.unmount();
            return Err(error).context("start WinFsp dispatcher");
        }

        log::info!(
            "mounted {} at {}",
            self.target.identity(),
            mount_point.display()
        );
        Ok(MountHandle {
            inner: Arc::new(MountInner {
                mount_point,
                target: self.target,
                host: Mutex::new(Some(host)),
            }),
        })
    }

    #[cfg(not(target_os = "windows"))]
    pub async fn mount(self) -> anyhow::Result<MountHandle> {
        let _ = self.validate()?;
        bail!("win-ifuse is only supported on Windows")
    }
}

async fn connect_source(
    provider: &dyn IdeviceProvider,
    source: &MountSource,
) -> anyhow::Result<AfcClient> {
    match source {
        MountSource::Media => AfcClient::connect(provider)
            .await
            .context("start AFC service"),
        MountSource::Root => AfcClient::new_afc2(provider)
            .await
            .context("start AFC2 service"),
        MountSource::Documents { bundle_id } => HouseArrestClient::connect(provider)
            .await
            .context("start House Arrest")?
            .vend_documents(bundle_id)
            .await
            .context("vend application Documents"),
        MountSource::Container { bundle_id } => HouseArrestClient::connect(provider)
            .await
            .context("start House Arrest")?
            .vend_container(bundle_id)
            .await
            .context("vend application container"),
    }
}

fn parse_network_address(input: &str) -> anyhow::Result<(IpAddr, Option<u32>)> {
    let input = input.trim();
    if input.is_empty() {
        bail!("network address cannot be empty");
    }
    let input = input
        .strip_prefix('[')
        .and_then(|value| value.strip_suffix(']'))
        .unwrap_or(input);
    let (address, scope_id) = match input.rsplit_once('%') {
        Some((address, scope)) if address.contains(':') => {
            let scope_id = scope
                .parse::<u32>()
                .context("IPv6 scope must be a numeric interface ID")?;
            (address, Some(scope_id))
        }
        _ => (input, None),
    };
    let address: IpAddr = address.parse().context("invalid network IP address")?;
    if scope_id.is_some() && !address.is_ipv6() {
        bail!("scope IDs are only valid for IPv6 addresses");
    }
    Ok((address, scope_id))
}

#[cfg(target_os = "windows")]
type Host = FileSystemHost<filesystem::IfuseFilesystem, CoarseGuard>;

#[cfg(target_os = "windows")]
struct MountInner {
    mount_point: PathBuf,
    target: DeviceTarget,
    host: Mutex<Option<Host>>,
}

#[cfg(not(target_os = "windows"))]
struct MountInner;

/// Owns a live mount. Clones refer to the same idempotently-unmounted mount.
#[derive(Clone)]
pub struct MountHandle {
    inner: std::sync::Arc<MountInner>,
}

impl MountHandle {
    #[cfg(target_os = "windows")]
    pub fn mount_point(&self) -> &Path {
        &self.inner.mount_point
    }

    #[cfg(target_os = "windows")]
    pub fn target(&self) -> &DeviceTarget {
        &self.inner.target
    }

    /// Stop the dispatcher and remove the mount point. Calling this more than once is safe.
    #[cfg(target_os = "windows")]
    pub async fn unmount(&self) -> anyhow::Result<()> {
        if let Some(mut host) = self.inner.host.lock().unwrap().take() {
            host.stop();
            host.unmount();
            log::info!("unmounted {}", self.inner.mount_point.display());
        }
        Ok(())
    }

    #[cfg(not(target_os = "windows"))]
    pub async fn unmount(&self) -> anyhow::Result<()> {
        Ok(())
    }
}

#[cfg(target_os = "windows")]
impl Drop for MountInner {
    fn drop(&mut self) {
        if let Ok(host) = self.host.get_mut() {
            if let Some(mut host) = host.take() {
                host.stop();
                host.unmount();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_required_builder_fields() {
        assert!(
            WinIfuseBuilder::usb("")
                .mount_point("M:")
                .validate()
                .is_err()
        );
        assert!(WinIfuseBuilder::usb("udid").validate().is_err());
        assert!(
            WinIfuseBuilder::usb("udid")
                .mount_point("M:")
                .validate()
                .is_ok()
        );
    }

    #[test]
    fn validates_house_arrest_bundle_id() {
        assert!(
            WinIfuseBuilder::usb("udid")
                .mount_point("M:")
                .source(MountSource::Documents {
                    bundle_id: "".into()
                })
                .validate()
                .is_err()
        );
    }

    #[test]
    fn parses_ipv4_and_scoped_ipv6() {
        assert_eq!(
            parse_network_address("192.0.2.1").unwrap(),
            ("192.0.2.1".parse().unwrap(), None)
        );
        assert_eq!(
            parse_network_address("fe80::1%3").unwrap(),
            ("fe80::1".parse().unwrap(), Some(3))
        );
        assert_eq!(
            parse_network_address("[2001:db8::1]").unwrap(),
            ("2001:db8::1".parse().unwrap(), None)
        );
        assert!(parse_network_address("fe80::1%ethernet").is_err());
    }
}
