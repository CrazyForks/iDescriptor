use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    let builder = CxxQtBuilder::new_qml_module(
        QmlModule::new("com.kdab.cxx_qt.demo").qml_file("../qml/Tabs.qml"),
    )
    .qt_module("Qml")
    .files([
        "src/lib.rs",
        "src/afc_services.rs",
        "src/afc2_services.rs",
        "src/service_manager.rs",
        "src/screenshot.rs",
        "src/hause_arrest.rs",
        "src/io_manager.rs",
        "src/query_sqlite.rs",
        "src/image_loader.rs",
        "src/bridge.rs",
        "src/apps.rs",
    ])
    .include_dir("include");

    let builder = unsafe {
        builder.cc_builder(|cc| {
            cc.file("src/thumbnail.cc");
            cc.file("src/heic_to_image.cc");
            cc.file("src/qinput_get_text.cc");
        })
    };
    builder.build();
}
