use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(
        QmlModule::new("com.kdab.cxx_qt.demo").qml_file("../qml/Tabs.qml"),
    )
    .qt_module("Qml")
    .files(["src/lib.rs","src/afc_services.rs","src/afc2_services.rs","src/service_manager.rs","src/screenshot.rs","src/hause_arrest.rs","src/io_manager.rs"])
    .build();
}