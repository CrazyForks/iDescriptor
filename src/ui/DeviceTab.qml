import QtQuick
import iDescriptor
import QtQuick.Layouts
import "." as App

Item {
    id: root

    Component.onCompleted: {
        App.DeviceContext.init()
    }

    Text {
        text: qsTr("Connected devices will appear here")
        anchors.centerIn: parent
        visible: App.DeviceContext.getVisibleDeviceCount() === 0
        color: palette.text
        font.pixelSize: 24
    }

    Repeater {
        model: App.DeviceContext.devices

        delegate: Item {
            id: deviceDelegate

            required property var model

            anchors.fill: parent
            visible: App.DeviceContext.currentDestination === "device"
                     && deviceDelegate.model.udid
                        === App.DeviceContext.currentDestinationId

            ColumnLayout {
                anchors.fill: parent
                Layout.fillWidth: true
                Layout.fillHeight: true

                DeviceSectionTabs {
                    // anchors.horizontalCenter: parent.horizontalCenter
                    // anchors.verticalCenter: parent.verticalCenter
                    // anchors.top: parent.top
                    // Layout.topMargin: Qt.platform.os === "windows" ? 5 : 0
                    Layout.alignment: Qt.AlignHCenter

                    currentSection: deviceDelegate.model.currentSection
                    onSectionRequested: function(sectionIndex) {
                        App.DeviceContext.selectDeviceSection(sectionIndex)
                    }
                }
                Device {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    device: deviceDelegate.model
                    udid: deviceDelegate.model.udid
                    info: deviceDelegate.model.info
                    currentSection: deviceDelegate.model.currentSection
                }
            }
        }
    }

    Repeater {
        model: App.DeviceContext.recoveryDevices

        delegate: Item {
            id: recoveryDelegate

            required property var model

            anchors.fill: parent
            visible: App.DeviceContext.currentDestination === "recoveryDevice"
                     && recoveryDelegate.model.id
                        === App.DeviceContext.currentDestinationId

            RecoveryDeviceInfo {
                anchors.fill: parent
                udid: recoveryDelegate.model.udid
                info: recoveryDelegate.model.info
            }
        }
    }

    Repeater {
        model: App.DeviceContext.pendingDevices

        delegate: Item {
            id: pendingDelegate

            required property var model

            anchors.fill: parent
            visible: App.DeviceContext.currentDestination === "pendingDevice"
                     && pendingDelegate.model.udid
                        === App.DeviceContext.currentDestinationId

            PendingDevice {
                anchors.fill: parent
                udid: pendingDelegate.model.udid
            }
        }
    }
}
