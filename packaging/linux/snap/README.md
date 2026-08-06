# Snap package

The Snap recipe is experimental. Device detection is not currently reliable
under strict confinement, so do not publish it until the required interfaces
have been verified.

The manifest follows the regular Linux package-manager build:

```bash
IDESCRIPTOR_PACKAGE_MANAGER_MESSAGE="Please update iDescriptor through the Snap Store." \
    cargo build --release --features package_manager
```

Snapcraft performs that Cargo build inside its `core24` build environment and
uses the KDE Neon 6 extension for the Qt 6 SDK and runtime.

## Build

Install Snapcraft, then run this from the repository root:

```bash
snapcraft --project-dir packaging/linux/snap
```

The explicit project directory is required because the manifest is kept with
the other Linux packaging files instead of in Snapcraft's conventional
`snap/` directory. The manifest's local source path points back to the
repository root, so run the command from a complete checkout with submodules.
