import QtQuick
import QtQuick.Layouts
import iDescriptor
import "." as App

Item {
    id: root

    Component.onCompleted: {
        App.DeviceContext.init();
    }

    Text {
        text: qsTr("Connected devices will appear here")
        anchors.centerIn: parent
        visible: !App.DeviceContext.showWelcomePage && App.DeviceContext.getVisibleDeviceCount() === 0
        color: palette.text
        font.pixelSize: 24
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: App.DeviceContext.showWelcomePage ? 1 : 0

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Repeater {
                model: App.DeviceContext.devices
                delegate: Item {
                    id: deviceDelegate

                    required property var model

                    anchors.fill: parent
                    visible: deviceDelegate.model.udid === App.DeviceContext.currentDeviceUdid
                    Device {
                        device: deviceDelegate.model
                        udid: deviceDelegate.model.udid
                        anchors.fill: parent
                        info: deviceDelegate.model.info
                        currentSection: deviceDelegate.model.currentSection
                    }
                }
            }

            Repeater {
                model: App.DeviceContext.recoveryDevices
                delegate: Item {
                    id: recoveryDelegate

                    required property var model

                    anchors.fill: parent
                    visible: recoveryDelegate.model.id === App.DeviceContext.currentRecoveryDeviceId
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
                    visible: pendingDelegate.model.udid === App.DeviceContext.currentPendingDeviceUdid

                    PendingDevice {
                        anchors.fill: parent
                        udid: pendingDelegate.model.udid
                    }
                }
            }
        }

        Welcome {
            id: welcomePage
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
