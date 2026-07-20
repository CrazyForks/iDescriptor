use thiserror::Error;

/// Convenient result alias used by all public z-updater operations.
pub type Result<T> = std::result::Result<T, ZUpdaterError>;

/// Errors that can occur while checking releases or downloading an update.
#[derive(Error, Debug)]
pub enum ZUpdaterError {
    /// Wraps file-system failures while creating or writing downloaded assets.
    #[error(transparent)]
    Io(#[from] std::io::Error),

    /// Wraps HTTP and response decoding failures from reqwest.
    #[error(transparent)]
    Http(#[from] reqwest::Error),

    /// Wraps invalid URL values supplied by an update asset.
    #[error(transparent)]
    Url(#[from] url::ParseError),

    /// Returned when the configured current version cannot be parsed.
    #[error("invalid current version `{0}`")]
    InvalidCurrentVersion(String),

    /// Returned when a release tag does not contain a semantic version.
    #[error("invalid release version `{0}`")]
    InvalidReleaseVersion(String),

    /// Returned when no usable platform-specific asset exists for a release.
    #[error("no matching asset found for {platform:?}/{architecture:?}")]
    NoMatchingAsset {
        /// Platform used while matching the release asset.
        platform: crate::Platform,
        /// CPU architecture used while matching the release asset.
        architecture: crate::Architecture,
    },

    /// Returned when the current target cannot be matched to a known platform.
    #[error("unsupported platform")]
    UnsupportedPlatform,

    /// Returned when the current target cannot be matched to a known architecture.
    #[error("unsupported architecture")]
    UnsupportedArchitecture,
}
