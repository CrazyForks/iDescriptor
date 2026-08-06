{
  lib,
  rustPlatform,
  src,
  cmake,
  pkg-config,
  qt6,
  openssl,
  libplist,
  libheif,
  glib,
  avahi,
  avahi-compat,
  ffmpeg,
  gst_all_1,
  libssh2,
  ifuse,
  fuse3,
  util-linux,
  coreutils,
  polkit,
}:

let
  manifest = builtins.fromTOML (builtins.readFile ../../../Cargo.toml);
  gstPluginsGoodQt6 = gst_all_1.gst-plugins-good.override {
    qt6Support = true;
  };
  gstPlugins = with gst_all_1; [
    gstreamer
    gst-plugins-base
    gstPluginsGoodQt6
    gst-plugins-bad
    gst-plugins-ugly
    gst-libav
  ];
  runtimePrograms = [
    coreutils
    fuse3
    ifuse
    polkit
    util-linux
  ];
in
rustPlatform.buildRustPackage {
  pname = "idescriptor";
  inherit (manifest.package) version;
  inherit src;

  cargoLock = {
    lockFile = ../../../Cargo.lock;
    # Cargo.lock contains pinned Windows-only winfsp Git dependencies. Nix
    # still vendors the complete lockfile when building this Linux package.
    allowBuiltinFetchGit = true;
  };
  buildFeatures = [ "package_manager" ];

  IDESCRIPTOR_PACKAGE_MANAGER_MESSAGE =
    "Please update iDescriptor with the Nix profile, Home Manager, or NixOS configuration that installed it.";

  nativeBuildInputs = [
    cmake
    pkg-config
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    avahi
    avahi-compat
    ffmpeg
    glib
    libheif
    libplist
    libssh2
    openssl
    qt6.qt5compat
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtlocation
    qt6.qtmultimedia
    qt6.qtpositioning
    qt6.qtserialport
    qt6.qtshadertools
    qt6.qtsvg
  ] ++ gstPlugins;

  postInstall = ''
    ln -s "$out/bin/idescriptor" "$out/bin/iDescriptor"

    install -Dm644 \
      io.github.idescriptor.iDescriptor.desktop \
      "$out/share/applications/io.github.idescriptor.iDescriptor.desktop"
    install -Dm644 \
      io.github.idescriptor.iDescriptor.metainfo.xml \
      "$out/share/metainfo/io.github.idescriptor.iDescriptor.metainfo.xml"

    for size in 16 32 256 512; do
      install -Dm644 \
        "packaging/shared/resources/app-icon/icon-$size.png" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/io.github.idescriptor.iDescriptor.png"
    done
  '';

  preFixup = ''
    qtWrapperArgs+=(
      --prefix PATH : "${lib.makeBinPath runtimePrograms}"
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${lib.makeSearchPath "lib/gstreamer-1.0" gstPlugins}"
    )
  '';

  meta = {
    description = "Free, open-source, cross-platform iDevice management tool";
    homepage = "https://github.com/iDescriptor/iDescriptor";
    license = lib.licenses.agpl3Only;
    maintainers = [ lib.maintainers.fn3x ];
    mainProgram = "idescriptor";
    platforms = lib.platforms.linux;
  };
}
