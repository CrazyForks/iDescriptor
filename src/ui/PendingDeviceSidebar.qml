import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./base"
import "." as App

Item {
    id: root

    required property string udid
    readonly property bool selectedDevice:
        App.DeviceContext.currentDestination === "pendingDevice"
        && App.DeviceContext.currentDestinationId === root.udid
    readonly property string shortUdid: root.udid.length > 10
        ? root.udid.slice(0, 10) + "…"
        : root.udid

    implicitWidth: 175
    implicitHeight: 58

    function selectDevice() {
        App.DeviceContext.selectPendingDevice(root.udid)
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: App.Theme.sidebarCornerRadius
        color: root.selectedDevice
            ? App.Theme.selectionSoft
            : headerHover.hovered ? App.Theme.hover : App.Theme.controlFill
        border.color: root.selectedDevice ? App.Theme.focus : App.Theme.controlStroke
        border.width: 1

        Behavior on color {
            ColorAnimation { duration: App.Theme.fastAnimation }
        }

        HoverHandler { id: headerHover }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: root.selectDevice()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            Image {
                source: "qrc:/resources/icons/iphone_gen3.svg"
                sourceSize.width: 30
                sourceSize.height: 30
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Pairing…")
                    color: App.Theme.text
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Label {
                    Layout.fillWidth: true
                    text: root.shortUdid
                    color: App.Theme.textMuted
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            Spinner {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                Layout.preferredWidth: 25
                Layout.preferredHeight: 25
                running: true
            }
        }
    }
}
