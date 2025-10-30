#!/bin/bash

set -e
VERSION=$1
if [ -z "$VERSION" ]; then
    echo "No version specified"
    exit 1
fi

export VERSION=$VERSION
export APPDIR=$PWD/AppDir
export GSTREAMER_VERSION=1.0

# Download linuxdeploy and linuxdeploy-plugin-qt if not already present
if [ ! -f linuxdeploy-x86_64.AppImage ]; then
    wget -c -nv "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
    chmod a+x linuxdeploy-x86_64.AppImage 
fi

if [ ! -f linuxdeploy-plugin-qt-x86_64.AppImage ]; then
    wget -c -nv "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage"
    chmod a+x linuxdeploy-plugin-qt-x86_64.AppImage 
fi

# Ensure patchelf is installed
if ! command -v patchelf &> /dev/null; then
    echo "ERROR: patchelf not found. Please install it with: sudo apt install patchelf"
    exit 1
fi

# Prepare AppDir structure
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Copy executable and icon
cp build/iDescriptor "$APPDIR/usr/bin/"
cp resources/icons/app-icon/icon.png "$APPDIR/usr/share/icons/hicolor/256x256/apps/iDescriptor.png"


# Copy ifuse
cp /usr/local/bin/ifuse "$APPDIR/usr/bin"

# Copy iproxy
cp /usr/local/bin/iproxy "$APPDIR/usr/bin"

# Bundle GStreamer plugins and helpers
plugins_target_dir="$APPDIR/usr/lib/gstreamer-$GSTREAMER_VERSION"
helpers_target_dir="$APPDIR/usr/lib/gstreamer1.0/gstreamer-$GSTREAMER_VERSION"

# Detect plugin dirs based on architecture
if [ -d /usr/lib/$(uname -m)-linux-gnu/gstreamer-$GSTREAMER_VERSION ]; then
    plugins_dir="/usr/lib/$(uname -m)-linux-gnu/gstreamer-$GSTREAMER_VERSION"
else
    plugins_dir="/usr/lib/gstreamer-$GSTREAMER_VERSION"
fi

helpers_dir="/usr/lib/$(uname -m)-linux-gnu/gstreamer1.0/gstreamer-1.0"

mkdir -p "$plugins_target_dir"
mkdir -p "$helpers_target_dir"

echo "Copying plugins into $plugins_target_dir"
for i in "$plugins_dir"/*; do
    [ -d "$i" ] && continue
    [ ! -f "$i" ] && echo "File does not exist: $i" && continue

    echo "Copying plugin: $i"
    cp "$i" "$plugins_target_dir"
done

# Set RPATH on plugins
for i in "$plugins_target_dir"/*; do
    [ -d "$i" ] && continue
    [ ! -f "$i" ] && echo "File does not exist: $i" && continue
    (file "$i" | grep -qv ELF) && echo "Ignoring non-ELF file: $i" && continue

    echo "Manually setting RPATH for $i"
    patchelf --set-rpath '$ORIGIN/..:$ORIGIN' "$i"
done

echo "Copying helpers into $helpers_target_dir"
for i in "$helpers_dir"/*; do
    [ -d "$i" ] && continue
    [ ! -f "$i" ] && echo "File does not exist: $i" && continue

    echo "Copying helper: $i"
    cp "$i" "$helpers_target_dir"
done

# Set RPATH on helper tools
for i in "$helpers_target_dir"/*; do
    [ -d "$i" ] && continue
    [ ! -f "$i" ] && echo "File does not exist: $i" && continue
    (file "$i" | grep -qv ELF) && echo "Ignoring non-ELF file: $i" && continue

    echo "Manually setting RPATH for $i"
    patchelf --set-rpath '$ORIGIN/../..' "$i"
done

mkdir -p "$APPDIR/apprun-hooks"

cat <<'EOF' > "$APPDIR/apprun-hooks/linuxdeploy-plugin-env.sh"
#!/bin/bash

export GST_REGISTRY_REUSE_PLUGIN_SCANNER="no"
export GST_PLUGIN_SYSTEM_PATH_1_0="${APPDIR}/usr/lib/gstreamer-1.0"
export GST_PLUGIN_PATH_1_0="${APPDIR}/usr/lib/gstreamer-1.0"

export GST_PLUGIN_SCANNER_1_0="${APPDIR}/usr/lib/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner"
export GST_PTP_HELPER_1_0="${APPDIR}/usr/lib/gstreamer1.0/gstreamer-1.0/gst-ptp-helper"

export IPROXY_BIN_APPIMAGE="${APPDIR}/usr/bin/iproxy"
export IFUSE_BIN_APPIMAGE="${APPDIR}/usr/bin/ifuse"
EOF

chmod +x "$APPDIR/apprun-hooks/linuxdeploy-plugin-env.sh"

# .desktop file
cp iDescriptor.desktop "$APPDIR/usr/share/applications/"

export LD_LIBRARY_PATH="$APPDIR/usr/local/lib:$LD_LIBRARY_PATH"
export LINUXDEPLOY_EXCLUDED_LIBRARIES="*sql*"
export QML_SOURCES_PATHS="./qml"


 ./linuxdeploy-x86_64.AppImage \
            --appdir ./AppDir \
            --desktop-file AppDir/usr/share/applications/iDescriptor.desktop \
	        --plugin qt \
            --exclude-library libGL,libGLX,libEGL,libOpenGL,libdrm,libva,libvdpau,libxcb,libxcb-glx,libxcb-dri2,libxcb-dri3,libX11,libXext,libXrandr,libXrender,libXfixes,libXau,libXdmcp,libqsqlmimer,libmysqlclient,libmysqlclient \
            --output appimage \
