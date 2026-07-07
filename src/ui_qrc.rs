use qmetaobject::qrc;

qrc!(pub qml,
    "/" {
        "src/ui/AlbumContents.qml",
        "src/ui/AppsTab.qml",
        "src/ui/BackupDetails.qml",
        "src/ui/BatteryIndicator.qml",
        "src/ui/Device.qml",
        "src/ui/DeviceContext.qml",
        "src/ui/DeviceGallery.qml",
        "src/ui/DeviceImage.qml",
        "src/ui/DeviceInfo.qml",
        "src/ui/DeviceTab.qml",
        "src/ui/Diagnose.qml",
        "src/ui/DiskUsage.qml",
        "src/ui/FileExplorer.qml",
        "src/ui/FilesSection.qml",
        "src/ui/Helpers.qml",
        "src/ui/HowToConnect.qml",
        "src/ui/IconLoader.qml",
        "src/ui/Jailbroken.qml",
        "src/ui/LoginDialog.qml",
        "src/ui/Main.qml",
        "src/ui/NetworkDevicesToConnect.qml",
        "src/ui/PreviewWindow.qml",
        "src/ui/Theme.qml",
        "src/ui/Settings.qml",
        // "src/ui/Updater.qml",
        "src/ui/SidebarTabButton.qml",
        "src/ui/StatusBar.qml",
        "src/ui/StatusWindow.qml",
        "src/ui/StatusWindowProcess.qml",
        "src/ui/TabButton.qml",
        "src/ui/Tabs.qml",
        "src/ui/Toolbox.qml",
        "src/ui/Welcome.qml",
        "src/ui/DevModeHelper.qml",
        "src/ui/qmldir",


        // base/
        "src/ui/base/AnimatedTab.qml",
        "src/ui/base/Spinner.qml",
        "src/ui/base/StateView.qml",
        "src/ui/base/ToolWindow.qml",
        "src/ui/base/DefaultWindow.qml",
        "src/ui/base/SectionBox.qml",

        // tools/
        "src/ui/tools/Airplay.qml",
        "src/ui/tools/CableInfo.qml",
        "src/ui/tools/QueryMobileGestalt.qml",
        "src/ui/tools/SimulateLocation.qml",
        "src/ui/tools/DevDiskImages.qml",
        "src/ui/tools/WirelessGalleryImport.qml",
        "src/ui/tools/IFuse.qml",
        "src/ui/tools/LiveScreen.qml",
        "src/ui/tools/NetworkDevices.qml",
        "src/ui/tools/SSHTerminalTool.qml",
        "src/ui/tools/SSHProcessWindow.qml",
        "src/ui/tools/BackupManager.qml",

        // app-store/
        "src/ui/app-store/AppDetails.qml",
        "src/ui/app-store/GetIpaPopup.qml",
        "src/ui/app-store/InstallAppPopup.qml",
        "src/ui/app-store/AppItem.qml",

        // installed-apps/
        "src/ui/installed-apps/AppTab.qml",
        "src/ui/installed-apps/InstalledApps.qml",
    }
);

#[cfg(target_os = "windows")]
qrc!(pub windows_qml,
    "/" {
        "src/ui/platform/windows/Index.qml",
        "src/ui/platform/windows/Main.qml",
        "src/ui/base/+windows/SidebarTabButton.qml",
        "src/ui/base/+windows/DefaultWindow.qml",
        "src/ui/base/+windows/ToolWindow.qml",
        "src/ui/base/+windows/Spinner.qml",
    }
);

#[cfg(target_os = "macos")]
qrc!(pub macos_qml,
    "/" {
        "src/ui/platform/macos/Main.qml"
    }
);
