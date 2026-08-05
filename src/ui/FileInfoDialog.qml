// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App
import "./base"

AnimatedDialog {
    id: dialog

    required property var afcClient
    required property string filePath
    required property string displayName

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(520, parent ? parent.width - 40 : 520)
    height: Math.min(480, parent ? parent.height - 40 : 480)
    modal: true
    focus: true
    title: qsTr("File Information")
    standardButtons: Dialog.Close
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function formattedType(type) {
        switch (type) {
        case "S_IFREG":
            return qsTr("Regular File (%1)").arg(type)
        case "S_IFDIR":
            return qsTr("Directory (%1)").arg(type)
        case "S_IFLNK":
            return qsTr("Symbolic Link (%1)").arg(type)
        case "S_IFBLK":
            return qsTr("Block Device (%1)").arg(type)
        case "S_IFCHR":
            return qsTr("Character Device (%1)").arg(type)
        case "S_IFIFO":
            return qsTr("FIFO (%1)").arg(type)
        case "S_IFSOCK":
            return qsTr("Socket (%1)").arg(type)
        default:
            return type || qsTr("Unknown")
        }
    }

    function addInformation(label, value) {
        informationModel.append({
            "label": label,
            "value": String(value)
        })
    }

    function load() {
        informationModel.clear()
        stateView.errorText = qsTr("Could not retrieve file information.")
        stateView.viewState = StateView.State.Loading
        afcClient.get_file_info(filePath)
    }

    function showInformation(info) {
        const size = Number(info.size)
        addInformation(qsTr("Name"), displayName)
        addInformation(qsTr("Path"), filePath)
        addInformation(qsTr("Type"), formattedType(info.type))
        addInformation(
            qsTr("Size"),
            qsTr("%1 (%2 bytes)").arg(App.Helpers.formatSize(size)).arg(size)
        )
        addInformation(qsTr("Allocated Blocks"), info.blocks)
        addInformation(qsTr("Created"), info.creation)
        addInformation(qsTr("Modified"), info.modified)
        addInformation(qsTr("Hard Links"), info.hardLinks)
        if (info.linkTarget)
            addInformation(qsTr("Link Target"), info.linkTarget)

        stateView.viewState = StateView.State.Content
    }

    ListModel {
        id: informationModel
    }

    Connections {
        target: dialog.afcClient

        function onFileInfoReady(filePath, info) {
            if (filePath !== dialog.filePath)
                return

            dialog.showInformation(info)
        }

        function onFileInfoFailed(filePath, error) {
            if (filePath !== dialog.filePath)
                return

            stateView.errorText = error || qsTr("Could not retrieve file information.")
            stateView.viewState = StateView.State.Error
        }
    }

    contentItem: StateView {
        id: stateView

        autoSwitchContent: false
        viewState: StateView.State.Loading
        retryable: true
        onRetryRequested: dialog.load()

        contentItem: ScrollView {
            anchors.fill: parent
            clip: true

            ListView {
                model: informationModel
                spacing: 0

                delegate: Rectangle {
                    required property string label
                    required property string value

                    width: ListView.view.width
                    implicitHeight: details.implicitHeight + 24
                    color: "transparent"
                    radius: App.Theme.sidebarCornerRadius

                    RowLayout {
                        id: details

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 16

                        Label {
                            Layout.preferredWidth: 130
                            text: label
                            color: App.Theme.textMuted
                            font.pixelSize: 13
                        }

                        Label {
                            Layout.fillWidth: true
                            text: value
                            color: App.Theme.text
                            wrapMode: Text.WrapAnywhere
                            textFormat: Text.PlainText
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }
    }
}
