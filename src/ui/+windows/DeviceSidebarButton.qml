import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import ".."

Item {
    id: root

    property string title: ""
    property string udid: ""
    required property string iconPath
    required property bool wireless
    readonly property bool selectedDevice:
        DeviceContext.currentDestination === "device"
        && DeviceContext.currentDestinationId === root.udid
    readonly property string displayTitle:
        title && title.length ? title : qsTr("Unknown device")

    implicitWidth: 175
    implicitHeight: 42

    function selectDevice() {
        DeviceContext.selectConnectedDevice(root.udid)
    }

    Menu {
        id: contextMenu

        MenuItem {
            text: qsTr("Remove")
            enabled: root.udid.length > 0
            onTriggered: DeviceContext.removeDevice(root.udid)
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.sidebarCornerRadius
        color: root.selectedDevice ? Theme.selectionSoft
                                   : deviceHover.hovered ? Theme.hover
                                                         : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.fastAnimation }
        }

        HoverHandler { id: deviceHover }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: root.selectDevice()
        }

        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: function(point) {
                contextMenu.x = point.position.x
                contextMenu.y = point.position.y
                contextMenu.open()
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 7

            Image {
                source: root.iconPath
                sourceSize.width: 27
                sourceSize.height: 27
                Layout.preferredWidth: 27
                Layout.preferredHeight: 27
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Label {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: root.displayTitle
                color: Theme.text
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            IconImage {
                visible: root.wireless
                source: "qrc:/resources/icons/qlementine-icons_wireless-1-16.svg"
                color: Theme.icon
                sourceSize.width: 15
                sourceSize.height: 15
                Layout.preferredWidth: 15
                Layout.preferredHeight: 15
                opacity: 0.75
            }
        }
    }
}
