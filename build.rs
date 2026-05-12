// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2021-2022 Adrian <adrian.eddy at gmail>

use cmake::build;
use std::env;
use std::fmt::Write;
use std::path::Path;
use std::process::Command;
use walkdir::WalkDir;

fn compile_qml(dir: &str, qt_include_path: &str, qt_library_path: &str) {
    let mut config = cc::Build::new();
    config.include(qt_include_path);
    config.include(&format!("{}/QtCore", qt_include_path));
    config.include(&format!("{}/QtQml", qt_include_path));

    println!("cargo:rerun-if-changed=src/live_reload.cpp");
    println!("cargo:rerun-if-changed=src/utils.rs");

    if cfg!(target_os = "macos") {
        config.include(format!("{}/QtCore.framework/Headers/", qt_library_path));
        config.include(format!("{}/QtQml.framework/Headers/", qt_library_path));
    }
    for f in std::env::var("DEP_QT_COMPILE_FLAGS")
        .unwrap()
        .split_terminator(';')
    {
        config.flag(f);
    }

    println!("cargo:rerun-if-changed={}", dir);

    let out_dir = env::var("OUT_DIR").unwrap();
    let out_dir = Path::new(&out_dir);
    let main_dir = env::var("CARGO_MANIFEST_DIR").unwrap();

    let mut files = Vec::new();
    let mut qrc = "<RCC>\n<qresource prefix=\"/\">\n".to_string();
    WalkDir::new(dir).into_iter().flatten().for_each(|entry| {
        let f_name = entry.path().to_string_lossy().replace('\\', "/");
        if f_name.ends_with(".qml") || f_name.ends_with(".js") {
            let _ = writeln!(qrc, "<file>{}</file>", f_name);

            let cpp_name = f_name
                .replace('/', "_")
                .replace(".qml", ".cpp")
                .replace(".js", ".cpp");
            let cpp_path = out_dir.join(cpp_name).to_string_lossy().to_string();

            config.file(&cpp_path);
            files.push((f_name, cpp_path));
        }
    });

    let qt_path = std::path::Path::new(qt_library_path).parent().unwrap();
    let compiler_path = if qt_path.join("libexec/qmlcachegen").exists() {
        qt_path
            .join("libexec/qmlcachegen")
            .to_string_lossy()
            .to_string()
    } else if qt_path.join("../macos/libexec/qmlcachegen").exists() {
        qt_path
            .join("../macos/libexec/qmlcachegen")
            .to_string_lossy()
            .to_string()
    } else if env::var("CARGO_CFG_TARGET_OS").unwrap() == "windows"
        && env::var("CARGO_CFG_TARGET_ARCH").unwrap() == "aarch64"
    {
        qt_path
            .join("../msvc2019_64/bin/qmlcachegen")
            .to_string_lossy()
            .to_string()
    } else {
        "qmlcachegen".to_string()
    };

    qrc.push_str("</qresource>\n</RCC>");
    let qrc_path = Path::new(&main_dir)
        .join("ui.qrc")
        .to_string_lossy()
        .to_string();
    std::fs::write(&qrc_path, qrc).unwrap();

    for (qml, cpp) in &files {
        assert!(
            Command::new(&compiler_path)
                .args(["--resource", &qrc_path, "-o", cpp, qml])
                .status()
                .unwrap()
                .success()
        );
    }

    let loader_path = out_dir
        .join("qmlcache_loader.cpp")
        .to_str()
        .unwrap()
        .to_string();
    assert!(
        Command::new(&compiler_path)
            .args([
                "--resource-file-mapping",
                &qrc_path,
                "-o",
                &loader_path,
                "ui.qrc"
            ])
            .status()
            .unwrap()
            .success()
    );

    config.file(&loader_path);

    std::fs::remove_file(&qrc_path).unwrap();

    config.cargo_metadata(false).compile("qmlcache");
    println!("cargo:rustc-link-lib=static:+whole-archive=qmlcache");
}

// TODO: we may need to do moc 
// fn find_moc(qt_library_path: &str) -> String {
//     let qt_path = Path::new(qt_library_path).parent().unwrap();
//     let candidates = [
//         qt_path.join("libexec/moc"),
//         qt_path.join("../macos/libexec/moc"),
//         qt_path.join("../msvc2019_64/bin/moc"),
//     ];
//     for c in candidates {
//         if c.exists() {
//             return c.to_string_lossy().to_string();
//         }
//     }
//     "moc".to_string()
// }

// fn run_moc(moc: &str, header: &str, out_dir: &Path) -> String {
//     let base = Path::new(header)
//         .file_stem()
//         .unwrap()
//         .to_string_lossy()
//         .to_string();
//     let moc_cpp = out_dir.join(format!("moc_{}.cpp", base));
//     assert!(
//         Command::new(moc)
//             .args([header, "-o", moc_cpp.to_str().unwrap()])
//             .status()
//             .unwrap()
//             .success()
//     );
//     moc_cpp.to_string_lossy().to_string()
// }

fn compile_bridge(qt_include_path: &str) {
    println!("compile_bridge");
    println!("cargo:rerun-if-changed=src/bridge.cpp");
    println!("cargo:rerun-if-changed=src/include/bridge.h");
    println!("cargo:rerun-if-changed=src/networkdeviceprovider.h");
    println!("cargo:rerun-if-changed=src/core/services/avahi/avahi_service.h");
    println!("cargo:rerun-if-changed=src/core/services/avahi/avahi_service.cpp");
    let dir_var = env::var("OUT_DIR").unwrap();
    // let out_dir = Path::new(&dir_var);
    // let moc = find_moc(&env::var("DEP_QT_LIBRARY_PATH").unwrap());

    let mut cc_build = cc::Build::new();
    cc_build
        .cpp(true)
        .file("src/bridge.cpp")
        // .file("src/core/services/avahi/avahi_service.cpp")
        // .include("src")
        .include(qt_include_path)
        .include(format!("{}/QtCore", qt_include_path))
        .include(format!("{}/QtGui", qt_include_path))
        .flag_if_supported("-std=c++17")
        .flag_if_supported("-Wno-deprecated-declarations");

    // for f in env::var("DEP_QT_COMPILE_FLAGS")
    //     .unwrap()
    //     .split_terminator(';')
    // {
    //     cc_build.flag(f);
    // }

    // for header in [
    //     "src/networkdeviceprovider.h",
    //     "src/core/services/avahi/avahi_service.h",
    // ] {
    //     if Path::new(header).exists() {
    //         let moc_cpp = run_moc(&moc, header, out_dir);
    //         cc_build.file(moc_cpp);
    //     }
    // }

    if let Ok(ffmpeg_dir) = std::env::var("FFMPEG_DIR") {
        cc_build.include(format!("{}/include", ffmpeg_dir));
        println!("cargo:rustc-link-search={}/lib", ffmpeg_dir);
        println!("cargo:rustc-link-search={}/lib64", ffmpeg_dir);
    } else {
        // Fallback to pkg-config on Linux
        if let Ok(lib) = pkg_config::Config::new()
            .atleast_version("58")
            .probe("libavformat")
        {
            for path in lib.include_paths {
                cc_build.include(path);
            }
        }
        let _ = pkg_config::Config::new().probe("libavcodec");
        let _ = pkg_config::Config::new().probe("libavutil");
        let _ = pkg_config::Config::new().probe("libswscale");
        let _ = pkg_config::Config::new().probe("avahi-client");
    }

    cc_build.compile("bridge");

    for lib in ["avformat", "avcodec", "avutil", "swscale", "avahi-client"] {
        println!("cargo:rustc-link-lib={}", lib);
    }
}

fn compile_uxplay() {
    let uxplay = cmake::Config::new("lib/uxplay")
        .build_target("uxplay")
        //no need for x11
        .define("NO_X11_DEPS", "ON") 
        .build();

    let build = uxplay.display();

    println!("cargo:rustc-link-search=native={build}/build");
    println!("cargo:rustc-link-search=native={build}/build/lib");
    println!("cargo:rustc-link-search=native={build}/build/renderers");
    println!("cargo:rustc-link-search=native={build}/build/lib/llhttp");
    println!("cargo:rustc-link-search=native={build}/build/lib/playfair");

    println!("cargo:rustc-link-lib=static=uxplay");
    println!("cargo:rustc-link-lib=static=renderers");
    println!("cargo:rustc-link-lib=static=airplay");
    println!("cargo:rustc-link-lib=static=llhttp");
    println!("cargo:rustc-link-lib=static=playfair");

    // TODO: don't depend on Qt6Core
    pkg_config::Config::new().probe("Qt6Core").unwrap();

    // gst stuff
    for pkg in &[
        "gstreamer-1.0",
        "gstreamer-app-1.0",
        "gstreamer-video-1.0",
        "gstreamer-audio-1.0",
    ] {
        pkg_config::Config::new().probe(pkg).unwrap();
    }

    pkg_config::Config::new().probe("openssl").unwrap();

    // Linux uses avahi
    pkg_config::Config::new().probe("avahi-compat-libdns_sd").unwrap();
    
    // FIXME: macOS and Windows
    // println!("cargo:rustc-link-lib=dns_sd");

    // glib
    pkg_config::Config::new().probe("glib-2.0").unwrap();
    pkg_config::Config::new().probe("gobject-2.0").unwrap();
    pkg_config::Config::new().probe("libplist-2.0").unwrap();
}

fn main() {
    println!("cargo:rerun-if-changed=src/main.rs");

    let qt_include_path = env::var("DEP_QT_INCLUDE_PATH").unwrap();
    let qt_library_path = env::var("DEP_QT_LIBRARY_PATH").unwrap();
    let qt_version = env::var("DEP_QT_VERSION").unwrap();

    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();

    if let Ok(out_dir) = env::var("OUT_DIR") {
        println!("cargo::rustc-check-cfg=cfg(compiled_qml)");
        if out_dir.contains("\\deploy\\build\\")
            || out_dir.contains("/deploy/build/")
            || target_os == "android"
            || target_os == "ios"
        {
            compile_qml("src/ui/", &qt_include_path, &qt_library_path);
            println!("cargo:rustc-cfg=compiled_qml");
        }
    }

    let mut config = cpp_build::Config::new();

    for f in env::var("DEP_QT_COMPILE_FLAGS")
        .unwrap()
        .split_terminator(';')
    {
        config.flag(f);
    }

    let mut add_pkg_includes = |pkg: &str| {
        let lib = pkg_config::Config::new()
            .cargo_metadata(false) 
            .probe(pkg)
            .unwrap_or_else(|e| panic!("pkg-config probe failed for {pkg}: {e}"));
        for p in lib.include_paths {
            config.include(p);
        }
    };

    add_pkg_includes("gstreamer-1.0");
    add_pkg_includes("gstreamer-app-1.0");
    add_pkg_includes("gstreamer-video-1.0");
    add_pkg_includes("gstreamer-audio-1.0");
    add_pkg_includes("glib-2.0");
    add_pkg_includes("gobject-2.0");


    let mut public_include = |name| {
        if cfg!(target_os = "macos") {
            config.include(format!("{}/{}.framework/Headers/", qt_library_path, name));
        }
        config.include(format!("{}/{}", qt_include_path, name));
    };
    public_include("QtCore");
    public_include("QtGui");
    public_include("QtQuick");
    public_include("QtQml");
    public_include("QtQuickControls2");

    let mut private_include = |name| {
        if cfg!(target_os = "macos") {
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
    private_include("QtGui");
    private_include("QtQuick");
    private_include("QtQml");

    match target_os.as_str() {
        "android" => {
            println!(
                "cargo:rustc-link-search={}/lib/arm64-v8a",
                std::env::var("FFMPEG_DIR").unwrap()
            );
            println!(
                "cargo:rustc-link-search={}/lib",
                std::env::var("FFMPEG_DIR").unwrap()
            );
            config.include(format!("{}/include", std::env::var("FFMPEG_DIR").unwrap()));
        }
        "macos" | "ios" => {
            println!(
                "cargo:rustc-link-search={}/lib",
                std::env::var("FFMPEG_DIR").unwrap()
            );
            println!("cargo:rustc-link-lib=static:+whole-archive=x264");
            println!("cargo:rustc-link-lib=static=x265");
        }
        "linux" => {
            // println!(
            //     "cargo:rustc-link-search={}",
            //     std::env::var("OPENCV_LINK_PATHS").unwrap()
            // // );
            // println!(
            //     "cargo:rustc-link-search={}/lib/{}",
            //     std::env::var("FFMPEG_DIR").unwrap(),
            //     std::env::var("FFMPEG_ARCH").unwrap_or("amd64".into())
            // );
            // println!(
            //     "cargo:rustc-link-search={}/lib",
            //     std::env::var("FFMPEG_DIR").unwrap()
            // );
            // println!("cargo:rustc-link-lib=static:+whole-archive=z");
            // if std::env::var("OPENCV_LINK_PATHS")
            //     .unwrap_or_default()
            //     .contains("vcpkg")
            // {
            //     std::env::var("OPENCV_LINK_LIBS")
            //         .unwrap()
            //         .split(',')
            //         .for_each(|lib| {
            //             println!("cargo:rustc-link-lib=static:+whole-archive={}", lib.trim())
            //         });
            // } else {
            //     std::env::var("OPENCV_LINK_LIBS")
            //         .unwrap()
            //         .split(',')
            //         .for_each(|lib| println!("cargo:rustc-link-lib={}", lib.trim()));
            // }
        }
        "windows" => {
            println!("cargo:rustc-link-arg=/EXPORT:NvOptimusEnablement");
            println!("cargo:rustc-link-arg=/EXPORT:AmdPowerXpressRequestHighPerformance");
            println!(
                "cargo:rustc-link-search={}",
                std::env::var("OPENCV_LINK_PATHS").unwrap()
            );
            println!(
                "cargo:rustc-link-search={}\\lib\\{}",
                std::env::var("FFMPEG_DIR").unwrap(),
                std::env::var("FFMPEG_ARCH").unwrap_or("x64".into())
            );
            println!(
                "cargo:rustc-link-search={}\\lib",
                std::env::var("FFMPEG_DIR").unwrap()
            );
            let mut res = winres::WindowsResource::new();
            res.set_icon("resources/app_icon.ico");
            res.set("FileVersion", env!("CARGO_PKG_VERSION"));
            res.set("ProductVersion", env!("CARGO_PKG_VERSION"));
            res.set("ProductName", "Gyroflow");
            res.set(
                "FileDescription",
                &format!("Gyroflow v{}", env!("CARGO_PKG_VERSION")),
            );
            res.compile().unwrap();
        }
        tos => panic!("unknown target os {:?}!", tos),
    }

    if let Ok(time) = std::time::SystemTime::now().duration_since(std::time::SystemTime::UNIX_EPOCH)
    {
        println!(
            "cargo:rustc-env=BUILD_TIME={}",
            (time.as_secs() - 1642516578) / 600
        ); // New version every 10 minutes
    }

    // !IMPORTANT
    config.include(&qt_include_path).build("src/main.rs");

    if target_os == "ios" {
        let out_dir = env::var("OUT_DIR").unwrap();
        for entry in Path::new(&out_dir).read_dir().unwrap() {
            let path = entry.unwrap().path();
            if path.is_file() && path.to_string_lossy().contains("qml_plugins.o") {
                println!("cargo:rustc-link-arg=-force_load");
                println!("cargo:rustc-link-arg={}", path.to_string_lossy());
                break;
            }
        }
    }

    compile_bridge(&qt_include_path);
    compile_uxplay();
}
