import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "." as App
import "./base"


AnimatedDialog {
    id: root

    modal: true
    focus: true
    standardButtons: Dialog.NoButton
    closePolicy: connecting ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
    width: Math.min(520, parent ? parent.width - 48 : 520)
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
        target: App.DeviceContext

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
            color: App.Theme.text
            font.pixelSize: 20
            font.weight: Font.Medium
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Select a .plist pairing file and enter the device IP address.")
            color: App.Theme.textMuted
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            implicitHeight: errorLabel.implicitHeight + 18
            radius: 10
            color: Qt.rgba(App.Theme.dangerText.r, App.Theme.dangerText.g, App.Theme.dangerText.b, 0.10)
            border.color: App.Theme.dangerText
            border.width: 1

            Label {
                id: errorLabel
                anchors.fill: parent
                anchors.margins: 9
                text: root.errorText
                color: App.Theme.dangerText
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 7

            Label {
                text: qsTr("Pairing file")
                color: App.Theme.textMuted
                font.pixelSize: 12
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    radius: 10
                    color: App.Theme.softBg
                    border.color: root.pairingFilePath.length > 0 ? App.Theme.controlStroke : App.Theme.dangerText
                    border.width: root.pairingFilePath.length > 0 ? 1 : 1

                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        text: root.pairingFilePath.length > 0 ? root.pairingFilePath : qsTr("Choose a .plist file")
                        color: root.pairingFilePath.length > 0 ? App.Theme.text : App.Theme.textMuted
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
                        color: parent.down ? App.Theme.pressed : (parent.hovered ? App.Theme.hover : App.Theme.softBg)
                        border.color: App.Theme.controlStroke
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
                color: App.Theme.textMuted
                font.pixelSize: 12
            }

            TextField {
                id: ipField
                Layout.fillWidth: true
                text: root.ipAddress
                enabled: !root.connecting
                placeholderText: qsTr("192.168.1.42")
                color: App.Theme.text
                selectedTextColor: App.Theme.textSelected
                selectionColor: App.Theme.selection
                onTextChanged: {
                    root.ipAddress = text
                    root.errorText = ""
                }

                background: Rectangle {
                    radius: 10
                    color: App.Theme.softBg
                    border.color: ipField.activeFocus ? App.Theme.focus
                                : root.ipAddress.trim().length > 0 ? App.Theme.controlStroke
                                                                  : App.Theme.dangerText
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
                    color: parent.hovered ? App.Theme.hover : "transparent"
                }
            }

            Button {
                text: root.connecting ? qsTr("Connecting...") : qsTr("Connect")
                enabled: root.canConnect
                padding: 10
                onClicked: root.startConnection()

                contentItem: Label {
                    text: parent.text
                    color: parent.enabled ? App.Theme.textSelected : App.Theme.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.weight: Font.Medium
                }

                background: Rectangle {
                    radius: 12
                    color: parent.enabled ? (parent.down ? App.Theme.accentPressed : App.Theme.accent)
                                          : App.Theme.softBg
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
        App.DeviceContext.tryToConnectToNetworkDeviceCustom(root.activeIpAddress, root.pairingFilePath)
    }
}
