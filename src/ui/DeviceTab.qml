import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import iDescriptor
import "." as App

Item {
    id: root

    Component.onCompleted: {
        App.DeviceContext.init()
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
        currentIndex:  App.DeviceContext.showWelcomePage ? 1 : 0

        RowLayout {
            // anchors.fill: parent
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            ScrollView {
                id: deviceSidebarScroll

                Layout.fillHeight: true
                Layout.preferredWidth: 185
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                ColumnLayout {
                    width: deviceSidebarScroll.availableWidth
                    height: Math.max(implicitHeight, deviceSidebarScroll.availableHeight)

                    Repeater {
                        model: App.DeviceContext.devices
                        delegate: Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: deviceButton.implicitHeight
                            Layout.leftMargin: 7
                            Layout.rightMargin: 7
                            readonly property var info: model.info
                            SidebarTabButton {
                                id : deviceButton
                                anchors.fill: parent
                                currentSection: model.currentSection
                                title: info.product_type
                                iconPath: info.placeholder_path
                                udid: info["UniqueDeviceID"]
                                wireless: info.is_wireless
                                onSectionChanged: {
                                    if (model.currentSection !== sectionIndex)
                                        model.currentSection = sectionIndex

                                    App.DeviceContext.selectConnectedDevice(info["UniqueDeviceID"])
                                }
                            }
                        }
                    }

                    Repeater {
                        model: App.DeviceContext.pendingDevices
                        delegate: Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: pendingButton.implicitHeight
                            Layout.leftMargin: 5
                            Layout.rightMargin: 5

                            PendingDeviceSidebar {
                                id: pendingButton
                                anchors.fill: parent
                                udid: model.udid
                            }
                        }
                    }

                    Repeater {
                        model: App.DeviceContext.recoveryDevices
                        delegate: Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: recoveryButton.implicitHeight
                            readonly property var info: model.info
                            RecoveryDeviceSidebar {
                                id: recoveryButton
                                anchors.fill: parent
                                title: model.text
                                deviceId: model.id
                                mode: info.mode
                            }
                        }
                    }

                    // spacer taker
                    Item {
                        Layout.fillHeight : true
                    }
                }
            }



            Repeater {
                model: App.DeviceContext.devices
                delegate:Item {
                    Layout.fillWidth : true
                    Layout.fillHeight : true
                    visible : model.udid === App.DeviceContext.currentDeviceUdid
                    Device {
                        device: model
                        udid: model.udid
                        anchors.fill: parent
                        info: model.info
                        currentSection: model.currentSection
                    }
                }
            }

            Repeater {
                model: App.DeviceContext.recoveryDevices
                delegate: Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: model.id === App.DeviceContext.currentRecoveryDeviceId
                    RecoveryDeviceInfo {
                        anchors.fill: parent
                        udid: model.udid
                        info: model.info
                    }
                }
            }

            Repeater {
                model: App.DeviceContext.pendingDevices
                delegate: Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: model.udid === App.DeviceContext.currentPendingDeviceUdid

                    PendingDevice {
                        anchors.fill: parent
                        udid: model.udid
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
