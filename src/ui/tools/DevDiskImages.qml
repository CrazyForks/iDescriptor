import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../base"
import "../" as App

ToolWindow {
    id: root
    width: 800
    height: 600
    title: qsTr("Developer Disk Images - iDescriptor")
    property string currentDeviceUdid: ""
    readonly property bool hasDevice: App.DeviceContext.devices && App.DeviceContext.devices.count > 0

    function selectedImageItem() {
        if (imageListView.currentIndex < 0)
            return null

        const item = DevImgsManager.get_item(imageListView.currentIndex)
        if (!item)
            return null

        return item
    }

    //TODO: listen for mount/unmount events and update the model accordingly
    Connections {
        target: DevImgsManager
        //image_download_finished
        onImage_download_finished: (version, index, success, error) => {
            if (error && error.length > 0) {
                console.error("Download failed for version", version, ":", error);
                // FIXME: show error message in UI
            }
            DevImgsManager.handle_download_finished(version)
            DevImgsManager.fetch_image_list(root.currentDeviceUdid)
        }
    }


    StateView {
        anchors.fill: parent
        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 0
            spacing: 0

            ColumnLayout {
                id: topBar
                Layout.fillWidth: true

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 10
                    spacing: 10
                    

                    ComboBox {
                        id: deviceComboBox
                        Layout.preferredWidth: 250
                        model: root.hasDevice ? App.DeviceContext.devices : [{ text: "No device connected", udid: "" }]
                        textRole: "text"
                        valueRole: "udid"
                        onModelChanged: {
                            if (root.hasDevice) {
                                root.currentDeviceUdid = deviceComboBox.currentValue
                                DevImgsManager.fetch_image_list(root.currentDeviceUdid)
                            }
                        }
                        onCurrentIndexChanged: {
                            console.log("Device selection changed to:", deviceComboBox.currentValue)
                            root.currentDeviceUdid = deviceComboBox.currentValue
                            //refresh
                            DevImgsManager.fetch_image_list(root.currentDeviceUdid)
                        }
                        enabled: root.hasDevice
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        id: mountButton
                        text: qsTr("Mount")
                        enabled: imageListView.currentIndex >= 0 && root.hasDevice
                        onClicked: {
                            const item = root.selectedImageItem()
                            if (!item) {
                                console.error("No developer disk image is selected.")
                                return
                            }

                            console.log("Mount button clicked for item:", item)
                            const version = item.version
                            const info = DevImgsManager.get_locations_for_version(version)
                            const exists = info["exists"]
                            if (!exists) {
                                console.error("Required files for version", version, "do not exist. Cannot mount.")
                                return;
                            }

                            const dmg_path = info["dmg"]
                            const sig_path = info["sig"]
                            if (!dmg_path || !sig_path) {
                                console.error("Invalid paths for version", version, ":", dmg_path, sig_path)
                                return;
                            }

                            const device = App.DeviceContext.getDevice(root.currentDeviceUdid)
                            if (!device) {
                                console.error("No device found for UDID:", root.currentDeviceUdid)
                                return;
                            }

                            App.Helpers.connectOnce(device.service_manager.dev_image_mounted,(version, success, is_locked) =>{ 
                                console.log("dev_image_mounted signal received for version:", version, "success:", success, "is_locked:", is_locked)
                                if (success) {
                                    console.log("Developer disk image mounted successfully for version:", version)
                                    DevImgsManager.fetch_image_list(root.currentDeviceUdid)
                                } else {
                                    if (is_locked) {
                                        console.error("Failed to mount developer disk image for version", version, ": device is locked")
                                    } else {
                                        console.error("Failed to mount developer disk image for version", version)
                                    }
                                }
                            })                            
                            
                            device.service_manager.mount_dev_image(version, dmg_path, sig_path)
                        }
                    }

                    Button {
                        id: checkMountedButton
                        text: qsTr("Check Mounted")
                        enabled: root.hasDevice
                        onClicked: DevImgsManager.check_mounted_image()
                    }
                }

                Label {
                    visible : !root.hasDevice
                    color : "red"
                    text: qsTr("No device connected. Please connect a device to check for developer disk images.")   
                }

                Label {
                    visible: root.hasDevice
                    color : "red"
                    text : DevImgsManager.mounted_image_info && DevImgsManager.mounted_image_info.success ? qsTr("Selected device seems to already have a developer disk image mounted") : qsTr("Could not check for mounted developer disk image, make sure the device is unlocked")
                }

                ListView {
                    id: imageListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    
                    model: DevImgsManager.image_model
                    clip: true
                    ScrollBar.vertical: ScrollBar { }
                    delegate: Item {
                        id: rowItem
                        width: imageListView.width
                        height: versionLabel.implicitHeight + 20 // enough padding
                        // Layout.margins: 10

                        // Highlight overlay 
                        Rectangle {
                            anchors.fill: parent
                            color: index % 2 === 0 ? Qt.lighter(palette.window, 1.5) : palette.window

                            Rectangle {
                                anchors.fill: parent
                                color: {
                                    if (imageListView.currentIndex === index)
                                        return '#40bdc9cf'
                                    if (mouseArea.containsMouse)
                                        return '#20bdc9cf'
                                    return "transparent"
                                }
                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }
                        }

                        // MouseArea 
                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            propagateComposedEvents: true
                            onClicked: function(mouse) {
                                imageListView.currentIndex = index
                                mountButton.enabled = true
                                // don't consume 
                                mouse.accepted = false  
                            }
                        }


                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 5
                            spacing: 10

                            // Version label
                            Label {
                                id: versionLabel
                                text: version
                                font.bold: true
                                color: {
                                    switch (model.compatibility) {
                                        case "Compatible": return "#2E7D32"
                                        case "MaybeCompatible": return "#F57C00"
                                        default: return "#000000"
                                    }
                                }
                            }

                            // Status labels (Mounted / Maybe compatible / Not compatible)
                            Label {
                                id: mountedLabel
                                text: qsTr("Mounted")
                                visible: model.is_mounted
                                color: "#1565C0"
                                font.bold: true
                            }
                            Label {
                                id: maybeLabel
                                text: qsTr("Maybe compatible")
                                visible: model.compatibility === "MaybeCompatible" && !model.is_mounted
                                color: "#F57C00"
                                font.bold: true
                                leftPadding: 10
                            }
                            Label {
                                id: incompatLabel
                                text: qsTr("Not compatible")
                                visible: model.compatibility === "Incompatible" && !model.is_mounted
                                color: "#D32F2F"
                                font.bold: true
                                leftPadding: 10
                            }

                            Item { Layout.fillWidth: true }

                            ProgressBar {
                                id: progressBar
                                visible: model.is_downloading
                                from: 0
                                to: 100
                                value: model.progress
                                Layout.preferredWidth: 120
                            }

                            // Download / Re‑download button
                            Button {
                                id: downloadButton
                                text: model.is_downloaded ? qsTr("Re‑download") : qsTr("Download")
                                property string version: model.version
                                enabled: true
                                onClicked: {
                                    if (model.is_downloading) {
                                        console.log("Cancel download for version:", version)
                                        DevImgsManager.cancel_download(version)
                                        // refresh
                                        DevImgsManager.fetch_image_list(root.currentDeviceUdid)
                                        return;
                                    }
                                    downloadButton.text = qsTr("Cancel")
                                    model.is_downloading = true
                                    model.progress = 0
                                    const started_to_download = DevImgsManager.download_image(version, index)
                                    // FIXME: show error message
                                    if (!started_to_download) {
                                        console.error("Failed to start download for version:", version)
                                    }
                                }
                            }
                        }
                    }
                }
            }

        }
    }
  

    // fetch the image list when the component is created.
    Component.onCompleted: {
        root.currentDeviceUdid = deviceComboBox.currentValue
        DevImgsManager.fetch_image_list(root.currentDeviceUdid)
        console.log("DevDiskImages.qml: Component completed, fetching image list.")

    }
}
