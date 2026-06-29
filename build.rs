use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=src/main.rs");
    println!("cargo:rerun-if-changed=src/bridge.cpp");
    println!("cargo:rerun-if-changed=src/include/bridge.h");
    println!("cargo:rerun-if-changed=src/networkdeviceprovider.h");
    println!("cargo:rerun-if-changed=src/core/services/dnssd/dnssd_service.h");
    println!("cargo:rerun-if-changed=src/core/services/dnssd/dnssd_service.cpp");
    println!("cargo:rerun-if-changed=src/core/services/avahi/avahi_service.h");
    println!("cargo:rerun-if-changed=src/core/services/avahi/avahi_service.cpp");
    println!("cargo:rerun-if-changed=src/cpp/CMakeLists.txt");
    println!("cargo:rerun-if-changed=lib/uxplay/uxplay.h");
    println!("cargo:rerun-if-changed=lib/uxplay/uxplay.cpp");
    println!("cargo:rerun-if-changed=src/native/platform/macos/macos.h");
    println!("cargo:rerun-if-changed=src/native/platform/macos/macos.mm");

    let qt_include_path = env::var("DEP_QT_INCLUDE_PATH").unwrap();
    let qt_library_path = env::var("DEP_QT_LIBRARY_PATH").unwrap();
    let qt_version = env::var("DEP_QT_VERSION").unwrap();
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();

    // ------------------------------------------------------------------
    // Build cpp_bridge via CMake
    // ------------------------------------------------------------------
    let out = cmake::Config::new("src/native")
        .build_target("cpp_bridge")
        .define("CMAKE_BUILD_TYPE", "Debug")
        .define("CMAKE_PREFIX_PATH", &qt_library_path)
        .build();

    let build_dir = out.join("build");

    // cpp_bridge
    println!("cargo:rustc-link-search=native={}", build_dir.display());
    println!("cargo:rustc-link-lib=static=cpp_bridge");

    // uxplay sub-libs built inside the cmake tree
    for sub in &[
        "uxplay_build",
        "uxplay_build/lib",
        "uxplay_build/renderers",
        "uxplay_build/lib/llhttp",
        "uxplay_build/lib/playfair",
    ] {
        println!(
            "cargo:rustc-link-search=native={}/{}",
            build_dir.display(),
            sub
        );
    }
    for lib in &["uxplay", "renderers", "airplay", "llhttp", "playfair"] {
        println!("cargo:rustc-link-lib=static={}", lib);
    }

    // These are deps of the static libs (uxplay/airplay/cpp_bridge) that the
    // Rust linker must resolve explicitly since static libs don't embed deps.
    pkg_config::Config::new().probe("openssl").unwrap();
    pkg_config::Config::new().probe("libplist-2.0").unwrap();
    pkg_config::Config::new().probe("glib-2.0").unwrap();
    pkg_config::Config::new().probe("gobject-2.0").unwrap();

    // FFmpeg
    if let Ok(ffmpeg_dir) = env::var("FFMPEG_DIR") {
        println!("cargo:rustc-link-search={}/lib", ffmpeg_dir);
        for lib in &["avformat", "avcodec", "avutil", "swscale"] {
            println!("cargo:rustc-link-lib={}", lib);
        }
    } else {
        let _ = pkg_config::Config::new().probe("libavformat");
        let _ = pkg_config::Config::new().probe("libavcodec");
        let _ = pkg_config::Config::new().probe("libavutil");
        let _ = pkg_config::Config::new().probe("libswscale");
    }

    // GStreamer
    for pkg in &[
        "gstreamer-1.0",
        "gstreamer-app-1.0",
        "gstreamer-video-1.0",
        "gstreamer-audio-1.0",
    ] {
        pkg_config::Config::new().probe(pkg).unwrap();
    }

    // Qt (macOS needs framework search path; Linux/Windows via pkg-config)
    if target_os == "macos" {
        println!("cargo:rustc-link-search=framework={}", qt_library_path);
        for fw in &["QtCore", "QtGui", "QtQml", "QtQuick", "QtQuickControls2"] {
            println!("cargo:rustc-link-lib=framework={}", fw);
        }
    } else {
        pkg_config::Config::new().probe("Qt6Core").unwrap();
    }

    // Windows: Bonjour
    if target_os == "windows" {
        let bonjour_sdk = env::var("BONJOUR_SDK")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("C:/Program Files/Bonjour SDK"));
        println!(
            "cargo:rustc-link-arg={}",
            bonjour_sdk.join("Lib/x64/dnssd.lib").display()
        );
    }

    // ------------------------------------------------------------------
    // cpp_build — compiles the cpp! macros in src/main.rs
    // ------------------------------------------------------------------
    let mut config = cpp_build::Config::new();

    for f in env::var("DEP_QT_COMPILE_FLAGS")
        .unwrap()
        .split_terminator(';')
    {
        config.flag(f);
    }

    let mut public_include = |name: &str| {
        if target_os == "macos" {
            config.include(format!("{}/{}.framework/Headers/", qt_library_path, name));
        }
        config.include(format!("{}/{}", qt_include_path, name));
    };
    public_include("QtCore");
    public_include("QtGui");
    public_include("QtQuick");
    public_include("QtQml");
    public_include("QtQuickControls2");

    let mut private_include = |name: &str| {
        if target_os == "macos" {
            config.include(format!(
                "{}/{}.framework/Headers/{}",
                qt_library_path, name, qt_version
            ));
            config.include(format!(
                "{}/{}.framework/Headers/{}/{}",
                qt_library_path, name, qt_version, name
            ));
        }
        config
            .include(format!("{}/{}/{}", qt_include_path, name, qt_version))
            .include(format!(
                "{}/{}/{}/{}",
                qt_include_path, name, qt_version, name
            ));
    };
    private_include("QtCore");
    private_include("QtQuick");
    private_include("QtQml");

    let mut add_pkg_includes = |pkg: &str| {
        if let Ok(lib) = pkg_config::Config::new().cargo_metadata(false).probe(pkg) {
            for p in lib.include_paths {
                config.include(p);
            }
        }
    };
    add_pkg_includes("gstreamer-1.0");
    add_pkg_includes("gstreamer-app-1.0");
    add_pkg_includes("gstreamer-video-1.0");
    add_pkg_includes("gstreamer-audio-1.0");
    add_pkg_includes("glib-2.0");
    add_pkg_includes("gobject-2.0");

    if target_os == "macos" {
        config.flag(&format!("-F{}", qt_library_path));
    }

    if let Ok(time) = std::time::SystemTime::now().duration_since(std::time::SystemTime::UNIX_EPOCH)
    {
        println!(
            "cargo:rustc-env=BUILD_TIME={}",
            (time.as_secs() - 1642516578) / 600
        );
    }

    // Compile the ObjC++ bridge
    if target_os == "macos" {
        cc::Build::new()
            .file("src/native/platform/macos/macos.mm")
            // .flag("-fobjc-arc")
            .flag("-std=c++17")
            .include("src/native/platform/macos")
            .cargo_metadata(false)
            .compile("mac_window");

        println!(
            "cargo:rustc-link-search=native={}",
            env::var("OUT_DIR").unwrap()
        );
        println!("cargo:rustc-link-lib=static=mac_window");

        // Link required Apple frameworks
        println!("cargo:rustc-link-lib=framework=AppKit");
        println!("cargo:rustc-link-lib=framework=Foundation");
        println!("cargo:rustc-link-lib=framework=QuartzCore");
    }

    config.include(&qt_include_path).build("src/main.rs");
}
