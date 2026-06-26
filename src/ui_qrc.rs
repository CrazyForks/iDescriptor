use qmetaobject::qrc;

qrc!(pub qml,
    "/" {
        "src/ui/AlbumContents.qml",
        "src/ui/App.qml",
        "src/ui/AppsTab.qml",
        "src/ui/Device.qml",
        "src/ui/DeviceContext.qml",
        "src/ui/DeviceGallery.qml",
        "src/ui/DeviceImage.qml",
        "src/ui/DeviceInfo.qml",
        "src/ui/DeviceTab.qml",
        "src/ui/DiskUsage.qml",
        "src/ui/FileExplorer.qml",
        "src/ui/FilesSection.qml",
        "src/ui/Helpers.qml",
        "src/ui/HowToConnect.qml",
        "src/ui/IconLoader.qml",
        "src/ui/LoginDialog.qml",
        "src/ui/Main.qml",
        "src/ui/NetworkDevicesToConnect.qml",
        "src/ui/PreviewWindow.qml",
        "src/ui/SidebarTabButton.qml",
        "src/ui/StatusBar.qml",
        "src/ui/StatusWindow.qml",
        "src/ui/StatusWindowProcess.qml",
        "src/ui/TabButton.qml",
        "src/ui/Tabs.qml",
        "src/ui/Toolbox.qml",
        "src/ui/Welcome.qml",
        "src/ui/qmldir",

        // base/
        "src/ui/base/AnimatedTab.qml",
        "src/ui/base/StateView.qml",
        "src/ui/base/ToolWindow.qml",

        // tools/
        "src/ui/tools/Airplay.qml",
        "src/ui/tools/CableInfo.qml",
        "src/ui/tools/QueryMobileGestalt.qml",
        "src/ui/tools/VirtualLocation.qml",
        "src/ui/tools/DevDiskImages.qml",
        "src/ui/tools/WirelessGalleryImport.qml",
        "src/ui/tools/IFuse.qml",
        "src/ui/tools/NetworkDevices.qml",

        // app-store/
        "src/ui/app-store/AppItem.qml",

        // installed-apps/
        "src/ui/installed-apps/AppTab.qml",
        "src/ui/installed-apps/InstalledApps.qml",
    }
);

#[cfg(target_os = "windows")]
qrc!(pub windows_qml,
    "/" {
        "src/ui/windows/Index.qml",
        "src/ui/windows/Main.qml",
        "src/ui/windows/SidebarTabButton.qml",
    }
);
