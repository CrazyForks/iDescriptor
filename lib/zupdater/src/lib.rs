// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

mod error;

use std::path::{Path, PathBuf};

use derive_builder::Builder;
use futures_util::StreamExt;
use regex::Regex;
use reqwest::{Client, Url};
use semver::Version;
use serde::Deserialize;
use tokio::io::AsyncWriteExt;

pub use error::{Result, ZUpdaterError};

/// Callback type used when an update is found during an update check.
pub type OnUpdate = Box<dyn Fn(Update) + Send + Sync>;

/// Callback type used to report download progress to a caller-owned UI.
pub type DownloadProgressCallback = Box<dyn Fn(DownloadProgress) + Send + Sync>;

/// Operating systems known by z-updater.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Platform {
    /// Microsoft Windows targets.
    Windows,
    /// Apple macOS targets.
    MacOs,
    /// Linux targets.
    Linux,
}

/// CPU architectures known by z-updater.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Architecture {
    /// x86_64/AMD64 targets.
    X86_64,
    /// 64-bit ARM/AArch64 targets.
    Arm64,
    /// 32-bit ARM targets.
    Arm,
}

/// Controls whether and how a GitHub release asset is selected.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum AssetPolicy {
    /// Select the normal asset for the configured platform and portability mode.
    #[default]
    PlatformDefault,
    /// Select a Windows installer package.
    WindowsInstaller,
    /// Select a Windows portable archive.
    WindowsPortable,
    /// Select a macOS disk image.
    MacDmg,
    /// Select a directly executable Linux AppImage.
    LinuxAppImage,
    /// Return release metadata without attaching a directly downloadable asset.
    NoDirectDownload,
}

/// Describes how the host application normally wants to handle a downloaded update.
#[derive(Clone, Debug, Default, Builder)]
#[builder(setter(into), default)]
pub struct UpdateProcedure {
    /// Whether the frontend should offer to open the downloaded file.
    pub open_file: bool,
    /// Whether the frontend should offer to reveal the downloaded file directory.
    pub open_file_dir: bool,
    /// Whether the frontend should quit the application before installation.
    pub quit_app: bool,
    /// Informative text a frontend may show beside the update prompt.
    pub informative_text: String,
    /// Main text a frontend may show in the update prompt.
    pub text: String,
}

/// Static metadata about the application and target used for update checks.
#[derive(Clone, Debug)]
pub struct UpdaterConfig {
    /// Repository in `owner/name` form, for example `iDescriptor/iDescriptor`.
    pub repo: String,
    /// Current app version. A leading `v` is accepted.
    pub current_version: String,
    /// Human-readable app name used for frontend display.
    pub application_name: String,
    /// Platform used when selecting release assets.
    pub platform: Platform,
    /// Architecture used when selecting release assets.
    pub architecture: Architecture,
    /// Whether portable assets should be selected when supported.
    pub is_portable: bool,
    /// Whether the app was installed by a package manager.
    pub package_manager_managed: bool,
    /// Policy used to select a downloadable release asset.
    pub asset_policy: AssetPolicy,
    /// Whether prerelease GitHub releases should be ignored.
    pub skip_prerelease: bool,
    /// Frontend instructions associated with this updater setup.
    pub update_procedure: UpdateProcedure,
    /// Optional message a frontend may show for package-manager-managed installs.
    pub package_manager_managed_message: Option<String>,
}

/// Headless updater that checks GitHub releases and emits update metadata to caller code.
#[derive(Builder)]
#[builder(pattern = "owned", build_fn(validate = "Self::validate"))]
pub struct Updater {
    /// Repository in `owner/name` form, for example `iDescriptor/iDescriptor`.
    #[builder(setter(into))]
    repo: String,
    /// Current app version. A leading `v` is accepted.
    #[builder(setter(into))]
    current_version: String,
    /// Human-readable app name used for frontend display.
    #[builder(setter(into))]
    application_name: String,
    /// Platform override for tests or cross-target checks.
    #[builder(default = "detect_platform().map_err(|err| err.to_string())?")]
    platform: Platform,
    /// Architecture override for tests or cross-target checks.
    #[builder(default = "detect_architecture().map_err(|err| err.to_string())?")]
    architecture: Architecture,
    /// Select portable assets when the platform supports them.
    #[builder(default)]
    is_portable: bool,
    /// Mark this install as package-manager-managed.
    #[builder(default)]
    package_manager_managed: bool,
    /// Choose which kind of release asset, if any, should be attached to an update.
    #[builder(default)]
    asset_policy: AssetPolicy,
    /// Ignore prerelease GitHub releases.
    #[builder(default = "true")]
    skip_prerelease: bool,
    /// Caller-owned prompt/open/quit instructions for this application.
    #[builder(default)]
    update_procedure: UpdateProcedure,
    /// Optional frontend message for package-manager-managed installs.
    #[builder(default, setter(into, strip_option))]
    package_manager_managed_message: Option<String>,
    /// Optional callback fired by `check_for_updates` when an update is found.
    #[builder(default, setter(custom))]
    on_update: Option<OnUpdate>,
    /// HTTP client used to talk to GitHub and download assets.
    #[builder(default = "default_client().map_err(|err| err.to_string())?")]
    client: Client,
}

impl UpdaterBuilder {
    /// Registers a callback that receives a complete `Update` when one is available.
    pub fn on_update<F>(mut self, callback: F) -> Self
    where
        F: Fn(Update) + Send + Sync + 'static,
    {
        self.on_update = Some(Some(Box::new(callback)));
        self
    }

    fn validate(&self) -> std::result::Result<(), String> {
        if let Some(repo) = &self.repo {
            if !repo.contains('/') {
                return Err("repo must be in `owner/name` form".to_string());
            }
        }

        if let Some(version) = &self.current_version {
            parse_version(version).map_err(|err| err.to_string())?;
        }

        Ok(())
    }
}

impl Updater {
    /// Returns a builder for the required updater setup.
    pub fn builder() -> UpdaterBuilder {
        UpdaterBuilder::default()
    }

    /// Returns the platform detected for this compilation target.
    pub fn detect_platform() -> Result<Platform> {
        detect_platform()
    }

    /// Returns the architecture detected for this compilation target.
    pub fn detect_architecture() -> Result<Architecture> {
        detect_architecture()
    }

    /// Returns a snapshot of configuration metadata useful to a frontend.
    pub fn config(&self) -> UpdaterConfig {
        UpdaterConfig {
            repo: self.repo.clone(),
            current_version: self.current_version.clone(),
            application_name: self.application_name.clone(),
            platform: self.platform,
            architecture: self.architecture,
            is_portable: self.is_portable,
            package_manager_managed: self.package_manager_managed,
            asset_policy: self.asset_policy,
            skip_prerelease: self.skip_prerelease,
            update_procedure: self.update_procedure.clone(),
            package_manager_managed_message: self.package_manager_managed_message.clone(),
        }
    }

    /// Checks GitHub releases and returns update information when a newer release exists.
    pub async fn check_for_updates(&self) -> Result<Option<Update>> {
        let releases = self.fetch_releases().await?;

        let Some(release) = self.find_newer_release(releases)? else {
            return Ok(None);
        };

        let asset =
            if self.package_manager_managed || self.asset_policy == AssetPolicy::NoDirectDownload {
                None
            } else {
                Some(self.matching_asset(&release)?)
            };

        let update = Update {
            application_name: self.application_name.clone(),
            current_version: parse_version(&self.current_version)?,
            version: parse_version(&release.tag_name)?,
            tag_name: release.tag_name,
            release_name: release.name,
            changelog: release.body.unwrap_or_default(),
            release_url: release.html_url,
            prerelease: release.prerelease,
            published_at: release.published_at,
            asset,
            platform: self.platform,
            architecture: self.architecture,
            is_portable: self.is_portable,
            package_manager_managed: self.package_manager_managed,
            asset_policy: self.asset_policy,
            update_procedure: self.update_procedure.clone(),
            package_manager_managed_message: self.package_manager_managed_message.clone(),
            client: self.client.clone(),
        };

        if let Some(on_update) = &self.on_update {
            on_update(update.clone());
        }

        Ok(Some(update))
    }

    /// Returns metadata for the release matching the running application version.
    pub async fn current_release(&self) -> Result<Option<Release>> {
        Ok(self
            .find_current_release(self.fetch_releases().await?)?
            .map(Release::from))
    }

    async fn fetch_releases(&self) -> Result<Vec<GitHubRelease>> {
        let url = format!("https://api.github.com/repos/{}/releases", self.repo);
        Ok(self
            .client
            .get(url)
            .send()
            .await?
            .error_for_status()?
            .json::<Vec<GitHubRelease>>()
            .await?)
    }

    fn find_current_release(&self, releases: Vec<GitHubRelease>) -> Result<Option<GitHubRelease>> {
        let current = parse_version(&self.current_version)?;

        for release in releases {
            if self.skip_prerelease && release.prerelease {
                continue;
            }

            let Ok(version) = parse_version(&release.tag_name) else {
                continue;
            };

            if version == current {
                return Ok(Some(release));
            }
        }

        Ok(None)
    }

    fn find_newer_release(&self, releases: Vec<GitHubRelease>) -> Result<Option<GitHubRelease>> {
        let current = parse_version(&self.current_version)?;

        for release in releases {
            if self.skip_prerelease && release.prerelease {
                continue;
            }

            let Ok(version) = parse_version(&release.tag_name) else {
                continue;
            };

            if version > current {
                return Ok(Some(release));
            }
        }

        Ok(None)
    }

    fn matching_asset(&self, release: &GitHubRelease) -> Result<UpdateAsset> {
        let pattern = asset_pattern(
            self.platform,
            self.architecture,
            self.is_portable,
            self.asset_policy,
        )?;
        let asset_regex = Regex::new(&pattern).expect("asset pattern should be valid regex");

        release
            .assets
            .iter()
            .find(|asset| asset_regex.is_match(&asset.name))
            .map(|asset| UpdateAsset {
                name: asset.name.clone(),
                label: asset.label.clone(),
                download_url: asset.browser_download_url.clone(),
                content_type: asset.content_type.clone(),
                size: asset.size,
                download_count: asset.download_count,
            })
            .ok_or(ZUpdaterError::NoMatchingAsset {
                platform: self.platform,
                architecture: self.architecture,
            })
    }
}

/// Public metadata describing an available update.
#[derive(Clone, Debug)]
pub struct Update {
    /// Human-readable app name supplied during setup.
    pub application_name: String,
    /// Version currently running.
    pub current_version: Version,
    /// Parsed version available for download or package-manager update.
    pub version: Version,
    /// Raw GitHub release tag name.
    pub tag_name: String,
    /// Optional GitHub release display name.
    pub release_name: Option<String>,
    /// Release body/changelog text.
    pub changelog: String,
    /// Browser URL for the GitHub release page.
    pub release_url: String,
    /// Whether this update came from a prerelease.
    pub prerelease: bool,
    /// GitHub publish timestamp when provided.
    pub published_at: Option<String>,
    /// Matching downloadable asset, absent for package-manager-managed installs.
    pub asset: Option<UpdateAsset>,
    /// Platform used when this update was selected.
    pub platform: Platform,
    /// Architecture used when this update was selected.
    pub architecture: Architecture,
    /// Whether portable asset selection was enabled.
    pub is_portable: bool,
    /// Whether this install should be updated through a package manager.
    pub package_manager_managed: bool,
    /// Policy used to select this update's downloadable asset.
    pub asset_policy: AssetPolicy,
    /// Frontend instructions associated with this update.
    pub update_procedure: UpdateProcedure,
    /// Optional frontend message for package-manager-managed installs.
    pub package_manager_managed_message: Option<String>,
    client: Client,
}

/// Public metadata for a GitHub release without platform-specific asset selection.
#[derive(Clone, Debug)]
pub struct Release {
    /// Raw GitHub release tag name.
    pub tag_name: String,
    /// Optional GitHub release display name.
    pub release_name: Option<String>,
    /// Release body/changelog text.
    pub changelog: String,
    /// Browser URL for the GitHub release page.
    pub release_url: String,
    /// Whether this is a prerelease.
    pub prerelease: bool,
    /// GitHub publish timestamp when provided.
    pub published_at: Option<String>,
}

impl From<GitHubRelease> for Release {
    fn from(release: GitHubRelease) -> Self {
        Self {
            tag_name: release.tag_name,
            release_name: release.name,
            changelog: release.body.unwrap_or_default(),
            release_url: release.html_url,
            prerelease: release.prerelease,
            published_at: release.published_at,
        }
    }
}

impl Update {
    /// Downloads the matched release asset into `destination_dir`.
    pub async fn download<P>(&self, destination_dir: P) -> Result<DownloadedUpdate>
    where
        P: AsRef<Path>,
    {
        self.download_inner(destination_dir, None).await
    }

    /// Downloads the matched release asset into `destination_dir` and reports byte progress.
    pub async fn download_with_progress<P, F>(
        &self,
        destination_dir: P,
        on_progress: F,
    ) -> Result<DownloadedUpdate>
    where
        P: AsRef<Path>,
        F: Fn(DownloadProgress) + Send + Sync,
    {
        self.download_inner(destination_dir, Some(&on_progress))
            .await
    }

    async fn download_inner<P>(
        &self,
        destination_dir: P,
        on_progress: Option<&(dyn Fn(DownloadProgress) + Send + Sync)>,
    ) -> Result<DownloadedUpdate>
    where
        P: AsRef<Path>,
    {
        let asset = self.asset.as_ref().ok_or(ZUpdaterError::NoMatchingAsset {
            platform: self.platform,
            architecture: self.architecture,
        })?;

        let url = Url::parse(&asset.download_url)?;
        let response = self.client.get(url).send().await?.error_for_status()?;
        let total_bytes = response.content_length().or(asset.size);
        let output_path = destination_dir.as_ref().join(&asset.name);

        tokio::fs::create_dir_all(destination_dir.as_ref()).await?;
        let mut file = tokio::fs::File::create(&output_path).await?;
        let mut downloaded_bytes = 0_u64;
        let mut stream = response.bytes_stream();

        while let Some(chunk) = stream.next().await {
            let chunk = chunk?;
            file.write_all(&chunk).await?;
            downloaded_bytes += chunk.len() as u64;

            if let Some(callback) = on_progress {
                callback(DownloadProgress {
                    downloaded_bytes,
                    total_bytes,
                });
            }
        }

        file.flush().await?;

        Ok(DownloadedUpdate {
            path: output_path,
            bytes: downloaded_bytes,
            asset: asset.clone(),
        })
    }
}

/// Public metadata describing a downloadable release asset.
#[derive(Clone, Debug)]
pub struct UpdateAsset {
    /// File name reported by GitHub.
    pub name: String,
    /// Optional asset label reported by GitHub.
    pub label: Option<String>,
    /// Direct browser download URL for the asset.
    pub download_url: String,
    /// Content type reported by GitHub.
    pub content_type: String,
    /// Asset size in bytes when provided.
    pub size: Option<u64>,
    /// GitHub download count.
    pub download_count: u64,
}

/// Download progress emitted after each received chunk.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DownloadProgress {
    /// Number of bytes written so far.
    pub downloaded_bytes: u64,
    /// Expected total byte count when the server reported one.
    pub total_bytes: Option<u64>,
}

impl DownloadProgress {
    /// Returns progress as a value from 0.0 to 1.0 when the total size is known.
    pub fn fraction(self) -> Option<f64> {
        self.total_bytes
            .filter(|total| *total > 0)
            .map(|total| self.downloaded_bytes as f64 / total as f64)
    }
}

/// Result returned after a release asset has been downloaded.
#[derive(Clone, Debug)]
pub struct DownloadedUpdate {
    /// Full path to the downloaded file.
    pub path: PathBuf,
    /// Total bytes written to disk.
    pub bytes: u64,
    /// Asset metadata used for the download.
    pub asset: UpdateAsset,
}

#[derive(Debug, Deserialize)]
struct GitHubRelease {
    tag_name: String,
    name: Option<String>,
    body: Option<String>,
    html_url: String,
    prerelease: bool,
    published_at: Option<String>,
    assets: Vec<GitHubAsset>,
}

#[derive(Debug, Deserialize)]
struct GitHubAsset {
    name: String,
    label: Option<String>,
    browser_download_url: String,
    content_type: String,
    size: Option<u64>,
    download_count: u64,
}

fn default_client() -> Result<Client> {
    Ok(Client::builder().user_agent("z-updater").build()?)
}

fn detect_platform() -> Result<Platform> {
    if cfg!(target_os = "windows") {
        Ok(Platform::Windows)
    } else if cfg!(target_os = "macos") {
        Ok(Platform::MacOs)
    } else if cfg!(target_os = "linux") {
        Ok(Platform::Linux)
    } else {
        Err(ZUpdaterError::UnsupportedPlatform)
    }
}

fn detect_architecture() -> Result<Architecture> {
    if cfg!(target_arch = "x86_64") {
        Ok(Architecture::X86_64)
    } else if cfg!(target_arch = "aarch64") {
        Ok(Architecture::Arm64)
    } else if cfg!(target_arch = "arm") {
        Ok(Architecture::Arm)
    } else {
        Err(ZUpdaterError::UnsupportedArchitecture)
    }
}

fn asset_pattern(
    platform: Platform,
    architecture: Architecture,
    is_portable: bool,
    asset_policy: AssetPolicy,
) -> Result<String> {
    let (platform, is_portable) = match asset_policy {
        AssetPolicy::PlatformDefault => (platform, is_portable),
        AssetPolicy::WindowsInstaller => (Platform::Windows, false),
        AssetPolicy::WindowsPortable => (Platform::Windows, true),
        AssetPolicy::MacDmg => (Platform::MacOs, false),
        AssetPolicy::LinuxAppImage => (Platform::Linux, false),
        AssetPolicy::NoDirectDownload => {
            return Err(ZUpdaterError::NoMatchingAsset {
                platform,
                architecture,
            });
        }
    };

    let pattern = match platform {
        Platform::Windows => {
            let arch = match architecture {
                Architecture::X86_64 => "x86_64",
                Architecture::Arm64 => "arm64",
                Architecture::Arm => return Err(ZUpdaterError::UnsupportedArchitecture),
            };

            if is_portable {
                format!(r"(?i).*-Windows_{arch}\.portable\.zip$")
            } else {
                format!(r"(?i).*-Windows_{arch}\.msi$")
            }
        }
        Platform::MacOs => match architecture {
            Architecture::X86_64 => r"(?i).*-Apple_Intel\.dmg$".to_string(),
            Architecture::Arm64 => r"(?i).*-Apple_Silicon\.dmg$".to_string(),
            Architecture::Arm => return Err(ZUpdaterError::UnsupportedArchitecture),
        },
        Platform::Linux => {
            let arch = match architecture {
                Architecture::X86_64 => "x86_64",
                Architecture::Arm64 => "arm64",
                Architecture::Arm => return Err(ZUpdaterError::UnsupportedArchitecture),
            };

            format!(r"(?i).*-Linux_{arch}\.AppImage$")
        }
    };

    Ok(pattern)
}

fn parse_version(version: &str) -> Result<Version> {
    let trimmed = version.trim().trim_start_matches('v');
    if let Ok(parsed) = Version::parse(trimmed) {
        return Ok(parsed);
    }

    let version_regex = Regex::new(r"(\d+(?:\.\d+){0,2})").expect("version regex should compile");
    let Some(captures) = version_regex.captures(trimmed) else {
        return Err(ZUpdaterError::InvalidReleaseVersion(version.to_string()));
    };

    let mut parts = captures[1].split('.').collect::<Vec<_>>();
    while parts.len() < 3 {
        parts.push("0");
    }

    Version::parse(&parts.join("."))
        .map_err(|_| ZUpdaterError::InvalidReleaseVersion(version.to_string()))
}

#[cfg(test)]
fn release_for_test(tag_name: &str, prerelease: bool, assets: Vec<GitHubAsset>) -> GitHubRelease {
    GitHubRelease {
        tag_name: tag_name.to_string(),
        name: Some(tag_name.to_string()),
        body: Some("changes".to_string()),
        html_url: "https://example.com/release".to_string(),
        prerelease,
        published_at: None,
        assets,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn progress_fraction_is_reported_when_total_is_known() {
        let progress = DownloadProgress {
            downloaded_bytes: 25,
            total_bytes: Some(100),
        };

        assert_eq!(progress.fraction(), Some(0.25));
    }

    #[test]
    fn detects_windows_portable_asset_pattern() {
        let pattern = asset_pattern(
            Platform::Windows,
            Architecture::X86_64,
            true,
            AssetPolicy::PlatformDefault,
        )
        .unwrap();
        let regex = Regex::new(&pattern).unwrap();

        assert!(regex.is_match("iDescriptor-Windows_x86_64.portable.zip"));
        assert!(!regex.is_match("iDescriptor-Windows_x86_64.msi"));
    }

    #[test]
    fn explicit_asset_policy_overrides_detected_platform() {
        let pattern = asset_pattern(
            Platform::Windows,
            Architecture::Arm64,
            false,
            AssetPolicy::LinuxAppImage,
        )
        .unwrap();
        let regex = Regex::new(&pattern).unwrap();

        assert!(regex.is_match("iDescriptor-v1.0.0-Linux_arm64.AppImage"));
        assert!(!regex.is_match("iDescriptor-v1.0.0-Linux_arm64.AppImage.zip"));
        assert!(!regex.is_match("iDescriptor-v1.0.0-Windows_arm64.msi"));
    }

    #[test]
    fn no_direct_download_policy_does_not_select_an_asset_pattern() {
        assert!(
            asset_pattern(
                Platform::Linux,
                Architecture::X86_64,
                false,
                AssetPolicy::NoDirectDownload,
            )
            .is_err()
        );
    }

    #[test]
    fn parses_short_and_prefixed_versions() {
        assert_eq!(parse_version("v1.2").unwrap(), Version::new(1, 2, 0));
        assert_eq!(
            parse_version("release-1.2.10").unwrap(),
            Version::new(1, 2, 10)
        );
    }

    #[test]
    fn finds_first_newer_non_prerelease() {
        let updater = Updater::builder()
            .repo("owner/repo")
            .current_version("1.0.0")
            .application_name("Example")
            .platform(Platform::Linux)
            .architecture(Architecture::X86_64)
            .build()
            .unwrap();

        let release = updater
            .find_newer_release(vec![
                release_for_test("v2.0.0-beta.1", true, Vec::new()),
                release_for_test("v1.1", false, Vec::new()),
            ])
            .unwrap()
            .unwrap();

        assert_eq!(release.tag_name, "v1.1");
    }

    #[test]
    fn finds_release_matching_current_version() {
        let updater = Updater::builder()
            .repo("owner/repo")
            .current_version("1.2.0")
            .application_name("Example")
            .platform(Platform::Linux)
            .architecture(Architecture::X86_64)
            .build()
            .unwrap();

        let release = updater
            .find_current_release(vec![
                release_for_test("v2.0.0", false, Vec::new()),
                release_for_test("v1.2", false, Vec::new()),
            ])
            .unwrap()
            .unwrap();

        assert_eq!(release.tag_name, "v1.2");
    }
}
