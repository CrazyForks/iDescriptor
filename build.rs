use cmake::build;
use core::panic;
use std::fmt::Write;
use std::path::Path;
use std::process::Command;
use walkdir::WalkDir;
use std::env;
use std::path::PathBuf;


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

        #[cfg(target_os = "linux")]
        {
            let _ = pkg_config::Config::new().probe("avahi-client");
        }
    }

    cc_build.compile("bridge");

    for lib in ["avformat", "avcodec", "avutil", "swscale"] {
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
    #[cfg(target_os = "linux")]
    {
        pkg_config::Config::new()
            .probe("avahi-compat-libdns_sd")
            .unwrap();
    }

    // FIXME: macOS and Windows
    // println!("cargo:rustc-link-lib=dns_sd");

    // glib
    pkg_config::Config::new().probe("glib-2.0").unwrap();
    pkg_config::Config::new().probe("gobject-2.0").unwrap();
    pkg_config::Config::new().probe("libplist-2.0").unwrap();
}

fn add_pkg_includes_cc(build: &mut cc::Build, pkg: &str) {
    if let Ok(lib) = pkg_config::Config::new().cargo_metadata(false).probe(pkg) {
        for p in lib.include_paths {
            build.include(p);
        }
    }
}

fn dirname_and_filename(path: &str) -> (&str, &str) {
    if let Some(pos) = path.rfind(['/']) {
        (&path[..pos], &path[pos + 1..])
    } else {
        ("", "")
    }
}

fn compile_ccp_codebase() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    let out_dir = std::env::var("OUT_DIR").unwrap();

    let moc_dir = format!("{}/{}", out_dir, "moc");
    let cpp_out_path = Path::new(&moc_dir);
    std::fs::create_dir_all(cpp_out_path).unwrap();

    match target_os.as_str() {
        "linux" => {
            let paths = [
                "src/core/services/avahi/avahi_service.cpp",
                "src/core/services/avahi/avahi_service.h",
                "src/networkdeviceprovider.h",
            ];

            let mut build = cc::Build::new();

            build.cpp(true);

            // .files([
            //     moc_out_file_clone,
            //     "src/core/services/avahi/avahi_service.cpp".to_string(),
            // ]);

            for path in paths {
                let (dir_name, file_name) = dirname_and_filename(path);
                // no need moc for cpp files
                if file_name.to_ascii_lowercase().ends_with(".cpp") {
                    build.file(path);
                    continue;
                };
                let file_out_dir = cpp_out_path.join(dir_name);
                std::fs::create_dir_all(&file_out_dir).unwrap();
                let moc_out_file =
                    file_out_dir.to_str().unwrap().to_owned() + &format!("/moc_{}.cpp", &file_name);

                Command::new("/usr/lib/qt6/moc")
                    .args([path, "-o", &moc_out_file])
                    .status()
                    .unwrap();
                build.file(moc_out_file);
                build.file(path);
            }

            add_pkg_includes_cc(&mut build, "Qt6Core");
            add_pkg_includes_cc(&mut build, "Qt6Gui");
            add_pkg_includes_cc(&mut build, "Qt6Qml");
            add_pkg_includes_cc(&mut build, "Qt6Quick");
            add_pkg_includes_cc(&mut build, "Qt6QuickControls2");

            build.compile("cpp_codebase");

            pkg_config::Config::new()
                .cargo_metadata(true)
                .probe("avahi-client")
                .unwrap();
        }
        "windows" => {
            let paths = [
                "src/core/services/dnssd/dnssd_service.cpp",
                "src/core/services/dnssd/dnssd_service.h",
                "src/networkdeviceprovider.h",
            ];

            let mut build = cc::Build::new();

            build.cpp(true);

            for path in paths {
                let (dir_name, file_name) = dirname_and_filename(path);
                // no need moc for cpp files
                if file_name.to_ascii_lowercase().ends_with(".cpp") {
                    build.file(path);
                    continue;
                };
                let file_out_dir = cpp_out_path.join(dir_name);
                std::fs::create_dir_all(&file_out_dir).unwrap();
                let moc_out_file =
                    file_out_dir.to_str().unwrap().to_owned() + &format!("/moc_{}.cpp", &file_name);

                let status = Command::new("C:\\msys64\\mingw64\\share\\qt6\\bin\\moc.exe")
                    .args([path, "-o", &moc_out_file])
                    .status()
                    .unwrap();

                assert!(status.success());
                
                build.file(moc_out_file);
                build.file(path);
            }

            add_pkg_includes_cc(&mut build, "Qt6Core");
            add_pkg_includes_cc(&mut build, "Qt6Gui");
            add_pkg_includes_cc(&mut build, "Qt6Qml");
            add_pkg_includes_cc(&mut build, "Qt6Quick");
            add_pkg_includes_cc(&mut build, "Qt6QuickControls2");


            let bonjour_sdk = if let Ok(sdk_path) = env::var("BONJOUR_SDK") {
                PathBuf::from(sdk_path)
            } else {
                // Try common Windows installation paths
                let possible_paths = vec![
                    "C:/Program Files/Bonjour SDK",
                    // "C:/Program Files (x86)/Bonjour SDK",
                    // "C:/Windows/System32",
                ];

                possible_paths
                    .iter()
                    .find(|p| PathBuf::from(p).join("Include/dns_sd.h").exists())
                    .map(|p| PathBuf::from(p))
                    .expect("Bonjour SDK not found. Please set BONJOUR_SDK environment variable.")
            };

            build.include(bonjour_sdk.join("Include")); 
            // println!("cargo:rustc-link-search=native={}", bonjour_sdk.join("Lib/x64").display());  // add this
            // println!("cargo:rustc-link-lib=dnssd");  
            println!("cargo:rustc-link-arg={}", bonjour_sdk.join("Lib/x64/dnssd.lib").display());

            build.compile("cpp_codebase");
        }
        os_ => panic!("building not supported on this platform"),
    };

}

fn main() {
    println!("cargo:rerun-if-changed=src/main.rs");
    println!("cargo:rerun-if-changed=src/live_reload.cpp");

    let qt_include_path = env::var("DEP_QT_INCLUDE_PATH").unwrap();
    let qt_library_path = env::var("DEP_QT_LIBRARY_PATH").unwrap();
    let qt_version = env::var("DEP_QT_VERSION").unwrap();

    println!("Qt lib path: {}", qt_library_path);

    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();


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

    if let Ok(time) = std::time::SystemTime::now().duration_since(std::time::SystemTime::UNIX_EPOCH)
    {
        println!(
            "cargo:rustc-env=BUILD_TIME={}",
            (time.as_secs() - 1642516578) / 600
        );
    }


    compile_bridge(&qt_include_path);
    compile_uxplay();
    compile_ccp_codebase();

    // workaround for windows for now, we need to handle this in compile_bridge  
    if target_os == "windows" {
        // Look for Bonjour SDK
        let bonjour_sdk = if let Ok(sdk_path) = env::var("BONJOUR_SDK") {
            PathBuf::from(sdk_path)
        } else {
            let possible_paths = vec![
                "C:/Program Files/Bonjour SDK",
                // "C:/Program Files (x86)/Bonjour SDK",
            ];

            possible_paths
                .iter()
                .find(|p| PathBuf::from(p).join("Include/dns_sd.h").exists())
                .map(|p| PathBuf::from(p))
                .expect("Bonjour SDK not found. Please set BONJOUR_SDK environment variable.")
        };
        println!("Found Bonjour SDK at: {}", bonjour_sdk.display());

        let include_path = bonjour_sdk.join("Include");
        config.include(&include_path);


        let out_dir = env::var("OUT_DIR").unwrap();
        let moc_dir = format!("{}/moc", out_dir);
        std::fs::create_dir_all(&moc_dir).unwrap();

        let headers_to_moc = [
            "src/core/services/dnssd/dnssd_service.h",
            "src/networkdeviceprovider.h",
        ];

        for header in &headers_to_moc {
            let file_name = Path::new(header).file_name().unwrap().to_str().unwrap();
            let moc_out = format!("{}/moc_{}.cpp", moc_dir, file_name);
            let status = Command::new("C:\\msys64\\mingw64\\share\\qt6\\bin\\moc.exe")
                .args([*header, "-o", &moc_out])
                .status()
                .unwrap();
            assert!(status.success(), "MOC failed for {}", header);
            config.file(&moc_out);
        }

        config.file("src/core/services/dnssd/dnssd_service.cpp");

        config.file("src/bridge.cpp");
        config.include(format!("{}/QtGui", qt_include_path));
        if let Ok(ffmpeg_dir) = std::env::var("FFMPEG_DIR") {
            config.include(format!("{}/include", ffmpeg_dir));
            println!("cargo:rustc-link-search={}/lib", ffmpeg_dir);
            println!("cargo:rustc-link-search={}/lib64", ffmpeg_dir);
            println!("cargo:rustc-link-arg={}/lib/avformat.lib", ffmpeg_dir);
            println!("cargo:rustc-link-arg={}/lib/avcodec.lib", ffmpeg_dir);
            println!("cargo:rustc-link-arg={}/lib/avutil.lib", ffmpeg_dir);
            println!("cargo:rustc-link-arg={}/lib/swscale.lib", ffmpeg_dir);
        } else {
            if let Ok(lib) = pkg_config::Config::new()
                .cargo_metadata(false)
                .atleast_version("58")
                .probe("libavformat")
            {
                for path in lib.include_paths {
                    config.include(path);
                }
                for path in lib.link_paths {
                    println!("cargo:rustc-link-search=native={}", path.display());
                }
            }
            for lib in ["avformat", "avcodec", "avutil", "swscale"] {
                println!("cargo:rustc-link-arg=-l{}", lib);
            }
        }

        println!("cargo:rustc-link-arg={}", bonjour_sdk.join("Lib/x64/dnssd.lib").display());

        println!("cargo:rustc-env=BONJOUR_INCLUDE_PATH={}", include_path.display());
    }

    config.include(&qt_include_path).build("src/main.rs");
}
