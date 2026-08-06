
## Why not use build.rs ???

Because building C/C++ libs with subdirs doesn't work well in build.rs. We had to implement a lot of logic to make it work and it was a pain to maintain. What worked on Linux didn't work on macOS and vice versa. 

This small CMakeLists.txt file is used to build the C/C++/Objc files. 

Without this you can still build the project but you will have to implement a lot of logic in build.rs to make it work. 

~100 lines of CMakeLists.txt replaced ~500 lines of code in build.rs.

Even though it fixes the build issues, it still has some problems. For example, we still have to link uxplay deps in build.rs like so

```rs
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
```




Another problem, we had to implement moc ourselfs which in itself is a huge thing for example


```rs
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

    let status = Command::new("/usr/lib/qt6/moc")
        .args([path, "-o", &moc_out_file])
        .status()
        .unwrap();
    assert!(status.success(), "MOC failed for {}", path);

    build.file(moc_out_file);
    build.file(path);
}
```


For all the reasons above we do not recommend using build.rs for building this part of the project.

Just linking to the built library is much easier


However, this may change in the future if we ever rewrite avahi/dnssd related code in Rust