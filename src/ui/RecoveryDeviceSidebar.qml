import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App

Item {
    id: root

    property string title: ""
    property string deviceId: ""
    required property string mode
    readonly property bool selectedDevice:
        App.DeviceContext.currentDestination === "recoveryDevice"
        && App.DeviceContext.currentDestinationId === deviceId
    readonly property string displayTitle: title && title.length ? title : qsTr("Recovery Device")

    implicitWidth: 200
    implicitHeight: card.implicitHeight

    // TODO: maybe we can do better here
    function selectDevice() {
        App.DeviceContext.selectRecoveryDevice(root.deviceId)
    }

    Rectangle {
        id: card
        width: root.width
        implicitHeight: contentColumn.implicitHeight + 10
        radius: App.Theme.sidebarCornerRadius
        color: root.selectedDevice ? App.Theme.hover : App.Theme.controlFill
        border.color: root.selectedDevice ? App.Theme.focus : App.Theme.controlStroke
        border.width: 1

        Behavior on color {
            ColorAnimation { duration: App.Theme.fastAnimation }
        }

        ColumnLayout {
            id: contentColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 5
            spacing: 5

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: headerColumn.implicitHeight

                HoverHandler { id: headerHover }

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: root.selectDevice()
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: headerHover.hovered ? App.Theme.hover : "transparent"
                }

                ColumnLayout {
                    id: headerColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.displayTitle
                        color: App.Theme.text
                        font.bold: true
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Label {
                        Layout.fillWidth: true
                        text: root.mode
                        color: App.Theme.textMuted
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
