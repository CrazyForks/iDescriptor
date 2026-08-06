// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import "../base"
import ".." as App

ToolWindow {
    id: root
    width: 560
    height: 620
    minimumWidth: 480
    minimumHeight: 560
    visible: true
    title: qsTr("Transfer Speed Test - iDescriptor")

    property var backend: null
    property int selectedSizeIndex: 1
    property int hoveredSizeIndex: -1
    readonly property var payloadSizes: [32, 128, 512]
    readonly property var transferState: backend ? backend.state : ({
        running: false,
        phase: "idle",
        totalBytes: 0,
        uploadBytes: 0,
        downloadBytes: 0,
        uploadProgress: 0,
        downloadProgress: 0,
        currentMiBps: 0,
        uploadMiBps: 0,
        downloadMiBps: 0,
        error: "backend_unavailable"
    })
    readonly property bool running: transferState.running === true
    readonly property bool complete: transferState.phase === "complete"
    readonly property string errorCode: transferState.error || ""

    function formatBytes(bytes) {
        return qsTr("%1 MiB").arg((Number(bytes) / (1024 * 1024)).toFixed(0))
    }

    function transferredText(bytes) {
        return qsTr("%1 / %2")
            .arg(formatBytes(bytes || 0))
            .arg(formatBytes(transferState.totalBytes || 0))
    }

    function speedText(value) {
        return Number(value || 0).toFixed(2)
    }

    function mbitText(value) {
        return qsTr("%1 Mbit/s").arg((Number(value || 0) * 8.388608).toFixed(2))
    }

    function inlineErrorText() {
        switch (root.errorCode) {
        case "invalid_size":
            return qsTr("Select a supported payload size.")
        case "insufficient_storage":
            return qsTr("The device does not have enough free storage for this test.")
        case "cleanup_failed":
            return qsTr("The test finished, but its temporary file could not be removed.")
        case "afc_failed":
            return qsTr("The transfer failed. Make sure the device is connected and unlocked.")
        case "backend_unavailable":
            return qsTr("The transfer service is unavailable for this device.")
        default:
            return ""
        }
    }

    Component.onCompleted: {
        root.backend = serviceFactory.create_transfer_speed_tester(root.udid, root.device.connectionId)
    }

    onClosing: {
        if (root.backend)
            root.backend.cancel_test()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        IconImage {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            source: "qrc:/resources/icons/material-symbols_cable-rounded.svg"
            color: App.Theme.icon
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Device Transfer Speed")
            color: App.Theme.text
            font.pixelSize: 18
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Measure upload and download speed over the current device connection.")
            color: App.Theme.textMuted
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Payload size")
            color: App.Theme.textMuted
            font.pixelSize: 12
        }

        Item {
            id: segmentedControl
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            enabled: !root.running

            Rectangle {
                anchors.fill: parent
                radius: App.Theme.sidebarCornerRadius
                color: App.Theme.softBg
                border.color: App.Theme.softBgBorder
                border.width: 1
            }

            Rectangle {
                id: selectedPill
                x: 4 + root.selectedSizeIndex * ((segmentedControl.width - 8) / 3)
                y: 4
                width: (segmentedControl.width - 8) / 3
                height: segmentedControl.height - 8
                radius: App.Theme.sidebarCornerRadius
                color: App.Theme.controlFill
                border.color: App.Theme.controlStroke
                border.width: 1

                Behavior on x {
                    NumberAnimation {
                        duration: App.Theme.fastAnimation
                        easing.type: Easing.OutCubic
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 0

                Repeater {
                    model: [qsTr("32 MiB"), qsTr("128 MiB"), qsTr("512 MiB")]

                    delegate: Item {
                        required property int index
                        required property string modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle {
                            anchors.fill: parent
                            radius: App.Theme.sidebarCornerRadius
                            visible: root.selectedSizeIndex !== index
                                && root.hoveredSizeIndex === index
                                && segmentedControl.enabled
                            color: App.Theme.hover
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: root.selectedSizeIndex === index
                                ? App.Theme.text
                                : App.Theme.textMuted
                            font.pixelSize: 13
                            font.weight: root.selectedSizeIndex === index
                                ? Font.DemiBold
                                : Font.Normal
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: segmentedControl.enabled
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onEntered: root.hoveredSizeIndex = index
                            onExited: {
                                if (root.hoveredSizeIndex === index)
                                    root.hoveredSizeIndex = -1
                            }
                            onClicked: root.selectedSizeIndex = index
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 122
            spacing: 12
            opacity: root.running ? 1 : 0
            enabled: root.running

            Behavior on opacity {
                NumberAnimation {
                    duration: App.Theme.mediumAnimation
                    easing.type: Easing.OutCubic
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        text: root.transferState.phase === "upload"
                            ? qsTr("Uploading…")
                            : qsTr("Upload")
                        color: App.Theme.textMuted
                        font.pixelSize: 12
                    }

                    Item { Layout.fillWidth: true }

                    Label {
                        text: root.transferredText(root.transferState.uploadBytes)
                        color: App.Theme.textMuted
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignRight
                    }
                }

                ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    value: Math.max(0, Math.min(1,
                        Number(root.transferState.uploadProgress || 0)))
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        text: root.transferState.phase === "download"
                            ? qsTr("Downloading…")
                            : qsTr("Download")
                        color: App.Theme.textMuted
                        font.pixelSize: 12
                    }

                    Item { Layout.fillWidth: true }

                    Label {
                        text: root.transferredText(root.transferState.downloadBytes)
                        color: App.Theme.textMuted
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignRight
                    }
                }

                ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    value: Math.max(0, Math.min(1,
                        Number(root.transferState.downloadProgress || 0)))
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            opacity: root.running || root.errorCode.length > 0 ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: App.Theme.mediumAnimation
                    easing.type: Easing.OutCubic
                }
            }

            Label {
                anchors.centerIn: parent
                width: parent.width
                visible: root.errorCode.length > 0
                text: root.inlineErrorText()
                color: App.Theme.dangerText
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            Row {
                anchors.centerIn: parent
                spacing: 6
                visible: root.running && root.errorCode.length === 0

                Label {
                    text: root.speedText(root.transferState.currentMiBps)
                    color: App.Theme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    font.family: "monospace"
                }

                Label {
                    anchors.baseline: parent.children[0].baseline
                    text: qsTr("MiB/s")
                    color: App.Theme.textMuted
                    font.pixelSize: 12
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 82
            opacity: root.complete ? 1 : 0
            enabled: root.complete

            Behavior on opacity {
                NumberAnimation {
                    duration: App.Theme.mediumAnimation
                    easing.type: Easing.OutCubic
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Upload")
                    color: App.Theme.textMuted
                    font.pixelSize: 12
                }

                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 5

                    Label {
                        text: root.speedText(root.transferState.uploadMiBps)
                        color: App.Theme.text
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        font.family: "monospace"
                    }

                    Label {
                        anchors.baseline: parent.children[0].baseline
                        text: qsTr("MiB/s")
                        color: App.Theme.textMuted
                        font.pixelSize: 12
                    }
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.mbitText(root.transferState.uploadMiBps)
                    color: App.Theme.textMuted
                    font.pixelSize: 11
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Download")
                    color: App.Theme.textMuted
                    font.pixelSize: 12
                }

                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 5

                    Label {
                        text: root.speedText(root.transferState.downloadMiBps)
                        color: App.Theme.text
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        font.family: "monospace"
                    }

                    Label {
                        anchors.baseline: parent.children[0].baseline
                        text: qsTr("MiB/s")
                        color: App.Theme.textMuted
                        font.pixelSize: 12
                    }
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.mbitText(root.transferState.downloadMiBps)
                    color: App.Theme.textMuted
                    font.pixelSize: 11
                }
            }
        }

        Item { Layout.fillHeight: true }

        Button {
            Layout.fillWidth: true
            text: root.running ? qsTr("Cancel") : qsTr("Start")
            enabled: !!root.backend
            onClicked: {
                if (root.running) {
                    root.backend.cancel_test()
                } else {
                    root.backend.start_test(root.payloadSizes[root.selectedSizeIndex])
                }
            }
        }
    }
}
