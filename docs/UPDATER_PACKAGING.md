# Updater and Packaging Guide

This document describes how iDescriptor selects updates, how each distribution
channel behaves, and how release/package maintainers must build the application.

The updater is split into three layers:

- `lib/zupdater/src/lib.rs` reads GitHub releases, compares versions, selects a
  matching release asset, and downloads direct-update assets.
- `src/updater.rs` identifies the installation channel and defines its asset,
  open, reveal, quit, and external-store behavior.
- `src/ui/Updater.qml` displays update status, release notes, download progress,
  package-manager instructions, and external-store buttons.

## Release discovery

The updater reads releases from `iDescriptor/iDescriptor` on GitHub. The running
version comes from `CARGO_PKG_VERSION`.

- Release tags may start with `v`, for example `v0.5.0`.
- Versions are compared using semantic-version rules.
- Prereleases are skipped.
- Release entries with an unrecognized version are skipped.
- The GitHub release body is displayed as the "What's new" text.

Package-manager and store builds still check GitHub for new versions and display
release notes. They do not download a GitHub release asset.

## Distribution features

The following Cargo features select Linux and Microsoft Store distribution
channels:

| Feature | Valid target | Purpose |
| --- | --- | --- |
| `appimage` | Linux | Direct AppImage download and launch |
| `flatpak` | Linux | Updates are managed through Flatpak |
| `package_manager` | Linux | Updates are managed by a downstream package manager |
| `windows_store` | Windows | Updates are managed through Microsoft Store |

Feature matching is intentionally strict:

- `windows_store` does not compile on a non-Windows target.
- `appimage`, `flatpak`, and `package_manager` do not compile on a non-Linux target.
- Only one of `appimage`, `flatpak`, and `package_manager` may be enabled.
- Invalid configurations produce a compile-time error instead of silently
  selecting another update channel.

Do not enable an updater distribution feature merely to make a build compile.
The feature must describe how the resulting package will actually be delivered.

## AppImage packages

Build an AppImage-targeted binary with:

```bash
cargo build --release --features appimage
```

The GitHub release must contain a raw AppImage with one of these names:

```text
*-Linux_x86_64.AppImage
*-Linux_arm64.AppImage
```

For example:

```text
iDescriptor-v0.5.0-Linux_x86_64.AppImage
```

`.AppImage.zip` is not accepted by the updater. After downloading the raw
AppImage to the user's `Downloads/iDescriptor` directory, iDescriptor gives it
executable permissions and can launch it directly. The currently running
application quits only after the new AppImage was successfully started.

The release publication process must upload the raw `.AppImage`. Creating it
locally is not sufficient if only a ZIP is attached to the GitHub release.

## Flatpak packages

Build the Flatpak version with:

```bash
cargo build --release --features flatpak
```

The updater checks for new GitHub releases but does not select or download a
GitHub asset. It tells the user to update through Flatpak or their software
center, shows the GitHub release notes, and provides an **Open Flatpak Page**
button.

The expected Flatpak application ID is:

```text
io.github.idescriptor.iDescriptor
```

The current updater page is:

```text
https://flathub.org/apps/io.github.idescriptor.iDescriptor
```

TODO: Verify that this is the final published Flatpak/Flathub URL when the
listing is released.

## Downstream package managers

Use the generic package-manager channel for Nix, Snap, Arch/AUR, distribution
repositories, and other downstream packages:

```bash
cargo build --release --features package_manager
```

The older CMake definitions `PACKAGE_MANAGER_MANAGED` and
`PACKAGE_MANAGER_HINT` do not configure the Rust updater. Maintainers must use
the Cargo feature and environment variable documented here.

This channel:

- checks GitHub for newer releases;
- displays the GitHub release notes;
- does not select or download a GitHub release asset;
- does not provide an external action button; and
- defaults to "Please use your package manager to update iDescriptor."

### Custom package-manager message

A maintainer may embed a custom message at build time with
`IDESCRIPTOR_PACKAGE_MANAGER_MESSAGE`:

```bash
IDESCRIPTOR_PACKAGE_MANAGER_MESSAGE="Please update iDescriptor using yay or paru." \
    cargo build --release --features package_manager
```

Another example:

```bash
IDESCRIPTOR_PACKAGE_MANAGER_MESSAGE="Open your software center to update iDescriptor." \
    cargo build --release --features package_manager
```

The value is compiled into the binary; it is not read from the user's runtime
environment. Changing it causes Cargo to rebuild iDescriptor. Leading and
trailing whitespace is removed. A missing or blank value uses the translated
generic message.

The custom variable is only consumed by `package_manager` builds. It does not
override Flatpak or Microsoft Store text.

Maintainers should keep the message concise and explain the exact action the
user needs to take. Do not include shell commands unless they are stable for all
users of that package.

## Microsoft Store packages

Build the Microsoft Store version on Windows with:

```powershell
cargo build --release --features windows_store
```

The updater checks GitHub for new versions, displays release notes, and does not
download an MSI or portable archive. The update page provides an
**Open Microsoft Store** button.

Until the final Store product ID is assigned, the native Store action searches
for `iDescriptor`:

```text
ms-windows-store://search/?query=iDescriptor
```

Its web fallback is:

```text
https://apps.microsoft.com/search?query=iDescriptor
```

TODO: Replace both search links with the final iDescriptor product-detail links
and verify that they open the exact published listing.

## Direct Windows releases

Normal Windows builds do not use a distribution feature. The updater determines
installed versus portable behavior from the running executable's location.

An executable under Program Files, Program Files (x86), or
`%LOCALAPPDATA%\Programs` is treated as installed. Other locations are treated
as portable.

Installed builds select:

```text
*-Windows_x86_64.msi
*-Windows_arm64.msi
```

After downloading an MSI, iDescriptor opens it and quits if opening succeeds.

Portable builds select:

```text
*-Windows_x86_64.portable.zip
*-Windows_arm64.portable.zip
```

The updater downloads the archive and reveals its directory. It does not
extract the portable ZIP or quit the running application.

## macOS releases

macOS builds do not require a distribution feature.

Intel builds select:

```text
*-Apple_Intel.dmg
```

Apple Silicon builds select:

```text
*-Apple_Silicon.dmg
```

After downloading, iDescriptor opens the DMG and quits if opening succeeds. The
user completes installation by dragging the application into Applications.

## Plain Linux builds

A Linux build without `appimage`, `flatpak`, or `package_manager` is treated as
a native/development build:

```bash
cargo build --release
```

It may report that a newer GitHub release exists and show its release notes, but
it has no configured direct-update asset. It is not treated as an AppImage.

Release packages intended for end users should select the feature that matches
their actual delivery channel.

## Asset requirements

Asset matching is case-insensitive but otherwise follows the suffixes documented
above. Supported architectures are:

- `x86_64`
- `arm64`

32-bit ARM direct-update assets are not supported.

If a direct-update build finds a newer release but no correctly named asset,
the update check fails with a no-matching-asset error. Always verify release
asset names before publishing.

## User-facing check behavior

Automatic update checks respect the user's "Automatically check for updates"
setting.

- An available update opens the updater window.
- No update is silent during an automatic check.
- Automatic check failures are logged but do not interrupt the user.
- Manual checks display checking, no-update, and error states.

All channels display release notes. Direct-update channels additionally display
the selected filename, size, download progress, destination, and the appropriate
open or reveal action.

## Maintainer checklist

Before publishing a package or release:

1. Select exactly the Cargo feature matching the delivery channel.
2. For a downstream package manager, set
   `IDESCRIPTOR_PACKAGE_MANAGER_MESSAGE` if the generic text is insufficient.
3. Confirm the package version matches the intended GitHub release tag.
4. For direct updates, verify the release asset name matches this document.
5. For AppImage releases, upload the raw `.AppImage`, not only a ZIP.
6. Test an update from the previous released version.
7. Verify release notes render in the updater.
8. For Flatpak or Microsoft Store, verify the external listing button opens the
   exact application page.
