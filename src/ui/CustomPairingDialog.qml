// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "./"
import "./base"


AnimatedDialog {
    id: root

    modal: true
    focus: true
    standardButtons: Dialog.NoButton
    closePolicy: connecting ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
    anchors.centerIn: Overlay.overlay
    width: Math.min(520, Overlay.overlay.width - 48)
    padding: 24

    property string pairingFilePath: ""
    property string ipAddress: ""
    property string activeIpAddress: ""
    property string errorText: ""
    property bool connecting: false
    readonly property bool canConnect: pairingFilePath.length > 0 && ipAddress.trim().length > 0 && !connecting

    

    FileDialog {
        id: pairingFileDialog
        title: qsTr("Choose pairing file")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Property List files (*.plist)")]
        currentFolder: Helpers.toFileUrl(QmlUtils.get_lockdown_path())
        onAccepted: {
            root.pairingFilePath = QmlUtils.url_to_path(selectedFile)
            root.errorText = ""
        }
    }

    Connections {
        target: core

        function onCustomInitFailed(ip, macAddress, error) {
            if (!root.connecting || ip !== root.activeIpAddress)
                return

            root.connecting = false
            root.errorText = error
        }
    }

    Connections {
        target: DeviceContext

        function onDeviceAdded(udid, mac) {
            if (!root.connecting)
                return

            root.connecting = false
            root.close()
        }
    }

  

    contentItem: ColumnLayout {
        spacing: 16

        Label {
            Layout.fillWidth: true
            text: qsTr("Connect with pairing file")
            color: Theme.text
            font.pixelSize: 20
            font.weight: Font.Medium
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Select a .plist pairing file and enter the device IP address.")
            color: Theme.textMuted
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            implicitHeight: errorLabel.implicitHeight + 18
            radius: 10
            color: Qt.rgba(Theme.dangerText.r, Theme.dangerText.g, Theme.dangerText.b, 0.10)
            border.color: Theme.dangerText
            border.width: 1

            Label {
                id: errorLabel
                anchors.fill: parent
                anchors.margins: 9
                text: root.errorText
                color: Theme.dangerText
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 7

            Label {
                text: qsTr("Pairing file")
                color: Theme.textMuted
                font.pixelSize: 12
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    radius: 10
                    color: Theme.softBg
                    border.color: root.pairingFilePath.length > 0 ? Theme.controlStroke : Theme.dangerText
                    border.width: root.pairingFilePath.length > 0 ? 1 : 1

                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        text: root.pairingFilePath.length > 0 ? root.pairingFilePath : qsTr("Choose a .plist file")
                        color: root.pairingFilePath.length > 0 ? Theme.text : Theme.textMuted
                        elide: Text.ElideMiddle
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Button {
                    text: qsTr("Choose")
                    enabled: !root.connecting
                    onClicked: pairingFileDialog.open()
                    padding: 10

                    background: Rectangle {
                        radius: 10
                        color: parent.down ? Theme.pressed : (parent.hovered ? Theme.hover : Theme.softBg)
                        border.color: Theme.controlStroke
                        border.width: 1
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 7

            Label {
                text: qsTr("IP address")
                color: Theme.textMuted
                font.pixelSize: 12
            }

            TextField {
                id: ipField
                Layout.fillWidth: true
                text: root.ipAddress
                enabled: !root.connecting
                placeholderText: qsTr("192.168.1.42")
                color: Theme.text
                selectedTextColor: Theme.textSelected
                selectionColor: Theme.selection
                onTextChanged: {
                    root.ipAddress = text
                    root.errorText = ""
                }

                background: Rectangle {
                    radius: 10
                    color: Theme.softBg
                    border.color: ipField.activeFocus ? Theme.focus
                                : root.ipAddress.trim().length > 0 ? Theme.controlStroke
                                                                  : Theme.dangerText
                    border.width: ipField.activeFocus ? 2 : 1
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 10

            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Cancel")
                enabled: !root.connecting
                onClicked: root.close()
                padding: 10

                background: Rectangle {
                    radius: 10
                    color: parent.hovered ? Theme.hover : "transparent"
                }
            }

            Button {
                text: root.connecting ? qsTr("Connecting...") : qsTr("Connect")
                enabled: root.canConnect
                padding: 10
                onClicked: root.startConnection()

                contentItem: Label {
                    text: parent.text
                    color: parent.enabled ? Theme.textSelected : Theme.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.weight: Font.Medium
                }

                background: Rectangle {
                    radius: 12
                    color: parent.enabled ? (parent.down ? Theme.accentPressed : Theme.accent)
                                          : Theme.softBg
                }
            }
        }
    }

    function startConnection() {
        if (!canConnect)
            return

        root.errorText = ""
        root.connecting = true
        root.activeIpAddress = root.ipAddress.trim()
        DeviceContext.tryToConnectToNetworkDeviceCustom(root.activeIpAddress, root.pairingFilePath)
    }
}
