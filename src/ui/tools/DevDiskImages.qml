// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

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
    property bool mountedImageChecked: false
    readonly property bool hasDevice: App.DeviceContext.devices && App.DeviceContext.devices.count > 0

    function selectedImageItem() {
        if (imageListView.currentIndex < 0)
            return null;

        const item = DevImgsManager.get_item(imageListView.currentIndex);
        if (!item)
            return null;

        return item;
    }

    function deviceIndexForUdid(udid) {
        if (!udid)
            return -1;

        for (let index = 0; index < App.DeviceContext.devices.count; ++index) {
            if (App.DeviceContext.devices.get(index).udid === udid)
                return index;
        }
        return -1;
    }

    function applyDeviceAt(index, fetchList) {
        let selectedUdid = "";
        if (root.hasDevice && index >= 0 && index < App.DeviceContext.devices.count)
            selectedUdid = App.DeviceContext.devices.get(index).udid;

        root.currentDeviceUdid = selectedUdid;
        root.mountedImageChecked = false;
        imageListView.currentIndex = -1;

        if (fetchList)
            DevImgsManager.fetch_image_list(selectedUdid, settingsManager.dev_disk_img_path());
    }

    function syncDeviceSelection(fetchList) {
        if (!root.hasDevice) {
            deviceComboBox.currentIndex = 0;
            root.applyDeviceAt(-1, fetchList);
            return;
        }

        let index = root.deviceIndexForUdid(root.currentDeviceUdid);
        if (index < 0)
            index = root.deviceIndexForUdid(root.udid);
        if (index < 0)
            index = root.deviceIndexForUdid(App.DeviceContext.currentDeviceUdid);
        if (index < 0)
            index = 0;

        deviceComboBox.currentIndex = index;
        root.applyDeviceAt(index, fetchList);
    }

    function compatibilityColor(compatibility, mounted) {
        if (mounted)
            return App.Theme.systemBlue;
        switch (compatibility) {
        case "Compatible":
            return App.Theme.systemGreen;
        case "MaybeCompatible":
            return App.Theme.systemOrange;
        case "Incompatible":
            return App.Theme.systemRed;
        default:
            return App.Theme.text;
        }
    }

    function statusText(compatibility, mounted) {
        if (mounted)
            return qsTr("Mounted");
        if (compatibility === "MaybeCompatible")
            return qsTr("Maybe compatible");
        if (compatibility === "Incompatible")
            return qsTr("Not compatible");
        return qsTr("Available");
    }

    function statusSymbol(compatibility, mounted) {
        if (mounted)
            return "✓";
        if (compatibility === "MaybeCompatible")
            return "!";
        if (compatibility === "Incompatible")
            return "×";
        return "✓";
    }

    //TODO: listen for mount/unmount events and update the model accordingly
    Connections {
        target: DevImgsManager

        function onImageDownloadFinished(version, index, success, error) {
            DevImgsManager.handle_download_finished(version);
            if (success) {
                App.Helpers.showInfo(root.contentItem, qsTr("Developer disk image %1 was downloaded successfully.").arg(version));
            } else {
                const detail = error && error.length > 0 ? error : qsTr("Unknown download error.");
                App.Helpers.showError(root.contentItem, qsTr("Could not download developer disk image %1: %2").arg(version).arg(detail));
            }
            DevImgsManager.fetch_image_list(root.currentDeviceUdid, settingsManager.dev_disk_img_path());
        }

        function onImageDownloadCancelled(version) {
            App.Helpers.showInfo(root.contentItem, qsTr("Download for developer disk image %1 was cancelled.").arg(version));
        }

        function onImageListRefreshFinished(udid, refreshed, success, error) {
            if (udid !== root.currentDeviceUdid)
                return;

            if (!success) {
                const detail = error && error.length > 0 ? error : qsTr("Unknown refresh error.");
                App.Helpers.showError(root.contentItem, qsTr("Could not refresh the developer disk image list: %1").arg(detail));
            } else if (refreshed) {
                App.Helpers.showInfo(root.contentItem, qsTr("The developer disk image list was refreshed."));
            }
        }

        function onMountedImageCheckFinished(udid, success, isMounted, isLocked, error) {
            if (udid !== root.currentDeviceUdid)
                return;

            root.mountedImageChecked = success;
            if (!success) {
                const detail = error && error.length > 0 ? error : qsTr("Unknown device error.");
                App.Helpers.showError(root.contentItem, qsTr("Could not check the mounted developer disk image: %1").arg(detail));
            } else if (isLocked) {
                App.Helpers.showWarning(root.contentItem, qsTr("The device is locked. Unlock it and check again."));
            } else if (isMounted) {
                App.Helpers.showInfo(root.contentItem, qsTr("A developer disk image is mounted on the selected device."));
            } else {
                App.Helpers.showInfo(root.contentItem, qsTr("No developer disk image is mounted on the selected device."));
            }

            if (success && !isLocked)
                DevImgsManager.fetch_image_list(root.currentDeviceUdid, settingsManager.dev_disk_img_path());
        }
    }

    Connections {
        target: App.DeviceContext

        function onDeviceAdded(udid, mac) {
            root.syncDeviceSelection(true);
        }

        function onDeviceRemoved(udid) {
            root.syncDeviceSelection(true);
        }
    }

    StateView {
        anchors.fill: parent
        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 0
            spacing: 16

            Rectangle {
                id: headerPanel
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.topMargin: 24
                implicitHeight: headerLayout.implicitHeight + 32
                radius: 10
                color: App.Theme.groupedBackground
                border.color: App.Theme.separator
                border.width: 1

                ColumnLayout {
                    id: headerLayout
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Label {
                                Layout.fillWidth: true
                                text: qsTr("Developer Disk Images")
                                color: App.Theme.text
                                font.pixelSize: 24
                                font.weight: Font.Light
                                lineHeight: 1.18
                                lineHeightMode: Text.ProportionalHeight
                            }


                            Label {
                                Layout.fillWidth: true
                                text: qsTr("Developer images allow you to use additional services on your iDevice. To mount one, the device must be unlocked.")
                                color : App.Theme.textMuted
                                wrapMode: Text.WordWrap
                                font.pixelSize: 10
                                font.weight: Font.Normal
                                lineHeightMode: Text.ProportionalHeight
                            }

                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            spacing: 8

                            Button {
                                id: mountButton
                                text: qsTr("Mount")
                                icon.source: "qrc:/resources/icons/mdi_disk.svg"
                                icon.width: 16
                                icon.height: 16
                                icon.color: enabled ? App.Theme.textSelected : App.Theme.textMuted
                                leftPadding: 14
                                rightPadding: 16
                                topPadding: 8
                                bottomPadding: 8
                                enabled: {
                                    const item = root.selectedImageItem();
                                    return root.hasDevice && item && item.is_downloaded
                                        && (item.compatibility === "Compatible" || item.compatibility === "MaybeCompatible");
                                }
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                palette.buttonText: mountButton.enabled ? App.Theme.textSelected : App.Theme.textMuted
                                background: Rectangle {
                                    radius: 8
                                    color: !mountButton.enabled ? App.Theme.softBg : mountButton.down ? App.Theme.accentPressed : mountButton.hovered ? App.Theme.accentHover : App.Theme.accent
                                    border.color: App.Theme.separator
                                    border.width: mountButton.enabled ? 0 : 1
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 220
                                            easing.type: Easing.InOutQuad
                                        }
                                    }
                                }
                                onClicked: {
                                    const item = root.selectedImageItem();
                                    if (!item) {
                                        App.Helpers.showWarning(root.contentItem, qsTr("Select a developer disk image first."));
                                        return;
                                    }

                                    console.log("Mount button clicked for item:", item);
                                    const version = item.version;
                                    const info = DevImgsManager.get_locations_for_version(version, settingsManager.dev_disk_img_path());
                                    const exists = info["exists"];
                                    if (!exists) {
                                        App.Helpers.showError(root.contentItem, qsTr("The required files for developer disk image %1 are missing.").arg(version));
                                        return;
                                    }

                                    const dmg_path = info["dmg"];
                                    const sig_path = info["sig"];
                                    if (!dmg_path || !sig_path) {
                                        App.Helpers.showError(root.contentItem, qsTr("The paths for developer disk image %1 are invalid.").arg(version));
                                        return;
                                    }

                                    const device = App.DeviceContext.getDevice(root.currentDeviceUdid);
                                    if (!device) {
                                        App.Helpers.showError(root.contentItem, qsTr("The selected device is no longer available."));
                                        return;
                                    }

                                    App.Helpers.connectOnce(device.service_manager.devImageMounted, (version, success, is_locked) => {
                                        console.log("devImageMounted signal received for version:", version, "success:", success, "is_locked:", is_locked);
                                        if (success) {
                                            console.log("Developer disk image mounted successfully for version:", version);
                                            App.Helpers.showInfo(root.contentItem, qsTr("Developer disk image %1 was mounted successfully.").arg(version));
                                            DevImgsManager.fetch_image_list(root.currentDeviceUdid, settingsManager.dev_disk_img_path());
                                        } else {
                                            if (is_locked) {
                                                App.Helpers.showWarning(root.contentItem, qsTr("Could not mount developer disk image %1 because the device is locked.").arg(version));
                                            } else {
                                                App.Helpers.showError(root.contentItem, qsTr("Could not mount developer disk image %1.").arg(version));
                                            }
                                        }
                                    });

                                    device.service_manager.mount_dev_image(version, dmg_path, sig_path);
                                }
                            }

                            Button {
                                id: checkMountedButton
                                text: qsTr("Check Mounted")
                                icon.source: "qrc:/resources/icons/ic_outline-refresh.svg"
                                icon.width: 16
                                icon.height: 16
                                icon.color: enabled ? App.Theme.icon : App.Theme.textMuted
                                enabled: root.hasDevice
                                leftPadding: 14
                                rightPadding: 16
                                topPadding: 8
                                bottomPadding: 8
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                palette.buttonText: checkMountedButton.enabled ? App.Theme.text : App.Theme.textMuted
                                background: Rectangle {
                                    radius: 8
                                    color: !checkMountedButton.enabled ? App.Theme.softBg : checkMountedButton.down ? App.Theme.pressed : checkMountedButton.hovered ? App.Theme.hover : App.Theme.elevatedSurface
                                    border.color: App.Theme.separator
                                    border.width: 1
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 220
                                            easing.type: Easing.InOutQuad
                                        }
                                    }
                                }
                                onClicked: DevImgsManager.check_mounted_image(root.currentDeviceUdid)
                            }

                            Button {
                                id: refreshButton
                                text: qsTr("Refresh")
                                icon.source: "qrc:/resources/icons/ic_outline-refresh.svg"
                                icon.width: 16
                                icon.height: 16
                                icon.color: enabled ? App.Theme.icon : App.Theme.textMuted
                                leftPadding: 14
                                rightPadding: 16
                                topPadding: 8
                                bottomPadding: 8
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                palette.buttonText: refreshButton.enabled ? App.Theme.text : App.Theme.textMuted
                                background: Rectangle {
                                    radius: 8
                                    color: refreshButton.down ? App.Theme.pressed : refreshButton.hovered ? App.Theme.hover : App.Theme.elevatedSurface
                                    border.color: App.Theme.separator
                                    border.width: 1
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 220
                                            easing.type: Easing.InOutQuad
                                        }
                                    }
                                }
                                onClicked: {
                                    DevImgsManager.refresh_image_list(root.currentDeviceUdid, settingsManager.dev_disk_img_path());
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        ComboBox {
                            id: deviceComboBox
                            Layout.preferredWidth: 250
                            Layout.preferredHeight: 36
                            model: root.hasDevice ? App.DeviceContext.devices : [
                                {
                                    text: qsTr("No device connected"),
                                    udid: ""
                                }
                            ]
                            textRole: "text"
                            valueRole: "udid"
                            enabled: root.hasDevice
                            leftPadding: 12
                            rightPadding: 32
                            font.pixelSize: 13
                            onActivated: function(index) {
                                root.applyDeviceAt(index, true);
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.maximumWidth: 360
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                radius: 10
                                color: {
                                    if (!root.hasDevice)
                                        return App.Theme.systemRed;
                                    if (root.mountedImageChecked && DevImgsManager.mounted_image_info.is_mounted)
                                        return App.Theme.systemBlue;
                                    return App.Theme.systemOrange;
                                }

                                Label {
                                    anchors.centerIn: parent
                                    text: root.hasDevice && root.mountedImageChecked && DevImgsManager.mounted_image_info.is_mounted ? "✓" : "!"
                                    color: App.Theme.textSelected
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: !root.hasDevice
                                color: App.Theme.systemRed
                                text: qsTr("No device connected. Please connect a device to check for developer disk images.")
                                wrapMode: Text.WordWrap
                                font.pixelSize: 13
                                lineHeight: 1.28
                                lineHeightMode: Text.ProportionalHeight
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: root.hasDevice
                                color: root.mountedImageChecked && DevImgsManager.mounted_image_info.is_mounted ? App.Theme.text : App.Theme.textMuted
                                text: {
                                    if (!root.mountedImageChecked)
                                        return qsTr("Use Check Mounted to inspect the selected device.");
                                    if (DevImgsManager.mounted_image_info.is_locked)
                                        return qsTr("The selected device is locked.");
                                    if (DevImgsManager.mounted_image_info.is_mounted)
                                        return qsTr("Selected device already has a developer disk image mounted.");
                                    return qsTr("No developer disk image is mounted on the selected device.");
                                }
                                wrapMode: Text.WordWrap
                                font.pixelSize: 13
                                lineHeight: 1.28
                                lineHeightMode: Text.ProportionalHeight
                            }
                        }
                    }
                }
            }

            ListView {
                id: imageListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
                leftMargin: 24
                rightMargin: 24
                bottomMargin: 24

                model: DevImgsManager.image_model
                clip: true
                ScrollBar.vertical: ScrollBar {}
                delegate: Item {
                    id: rowItem
                    width: imageListView.width - imageListView.leftMargin - imageListView.rightMargin
                    height: 64

                    Rectangle {
                        id: rowBackground
                        anchors.fill: parent
                        radius: 10
                        color: {
                            if (imageListView.currentIndex === index)
                                return App.Theme.selectionSoft;
                            if (mouseArea.containsMouse)
                                return App.Theme.selectionHover;
                            return App.Theme.rowSurface;
                        }
                        border.color: imageListView.currentIndex === index ? App.Theme.selectionStroke : App.Theme.separator
                        border.width: 1
                        Behavior on color {
                            ColorAnimation {
                                duration: 220
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }

                    // MouseArea
                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        propagateComposedEvents: true
                        onClicked: function (mouse) {
                            imageListView.currentIndex = index;
                            // don't consume
                            mouse.accepted = false;
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 16

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            // Version label
                            Label {
                                id: versionLabel
                                Layout.fillWidth: true
                                text: version
                                color: root.compatibilityColor(model.compatibility, model.is_mounted)
                                elide: Text.ElideRight
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    radius: 9
                                    color: root.compatibilityColor(model.compatibility, model.is_mounted)
                                    visible: root.currentDeviceUdid.length

                                    Label {
                                        anchors.centerIn: parent
                                        text: root.statusSymbol(model.compatibility, model.is_mounted)
                                        color: App.Theme.textSelected
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                // Status labels (Mounted / Maybe compatible / Not compatible)
                                Label {
                                    id: statusLabel
                                    Layout.fillWidth: true
                                    text: root.statusText(model.compatibility, model.is_mounted)
                                    color: App.Theme.textMuted
                                    elide: Text.ElideRight
                                    font.pixelSize: 12
                                    font.weight: Font.Normal
                                    visible: root.currentDeviceUdid.length
                                }
                            }
                        }

                        ProgressBar {
                            id: progressBar
                            visible: model.is_downloading
                            from: 0
                            to: 100
                            value: model.progress
                            Layout.preferredWidth: 136
                            Layout.preferredHeight: 8
                            background: Rectangle {
                                implicitWidth: 136
                                implicitHeight: 8
                                radius: 4
                                color: App.Theme.softBg
                                border.color: App.Theme.separator
                                border.width: 1
                            }
                            contentItem: Item {
                                implicitWidth: 136
                                implicitHeight: 8

                                Rectangle {
                                    width: progressBar.visualPosition * parent.width
                                    height: parent.height
                                    radius: 4
                                    color: App.Theme.systemBlue
                                    Behavior on width {
                                        NumberAnimation {
                                            duration: 220
                                            easing.type: Easing.InOutQuad
                                        }
                                    }
                                }
                            }
                        }

                        // Download / Re-download button
                        Button {
                            id: downloadButton
                            text: model.is_downloading ? qsTr("Cancel") : (model.is_downloaded ? qsTr("Re-download") : qsTr("Download"))
                            property string version: model.version
                            Layout.preferredHeight: 34
                            leftPadding: 14
                            rightPadding: 14
                            enabled: true
                            contentItem: Label {
                                text: downloadButton.text
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: model.is_downloading ? App.Theme.systemRed : App.Theme.text
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            background: Rectangle {
                                radius: 8
                                color: downloadButton.down ? App.Theme.pressed : downloadButton.hovered ? App.Theme.hover : App.Theme.elevatedSurface
                                border.color: model.is_downloading ? App.Theme.systemRed : App.Theme.separator
                                border.width: 1
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 220
                                        easing.type: Easing.InOutQuad
                                    }
                                }
                            }
                            onClicked: {
                                if (model.is_downloading) {
                                    console.log("Cancel download for version:", version);
                                    if (!DevImgsManager.cancel_download(version))
                                        App.Helpers.showError(root.contentItem, qsTr("Could not cancel the download for developer disk image %1.").arg(version));
                                    return;
                                }
                                const started_to_download = DevImgsManager.download_image(version, index, settingsManager.dev_disk_img_path());
                                if (!started_to_download) {
                                    console.error("Failed to start download for version:", version);
                                    App.Helpers.showError(root.contentItem, qsTr("Could not start the download for developer disk image %1.").arg(version));
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
        root.syncDeviceSelection(true);
        console.log("DevDiskImages.qml: Component completed, fetching image list for device:", root.currentDeviceUdid, "in directory:", settingsManager.dev_disk_img_path());
        console.log("DevDiskImages.qml: Component completed, fetching image list.");
    }
}
