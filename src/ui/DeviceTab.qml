import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import iDescriptor 1.0
import "." as App

Item {
    id: root

    Component.onCompleted: {
        App.DeviceContext.init()
    }

    Text {
        text: qsTr("Connected devices will appear here")
        anchors.centerIn: parent
        visible: !App.DeviceContext.showWelcomePage && App.DeviceContext.devices.count === 0
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

            ColumnLayout {
                Layout.fillHeight : true
                Layout.preferredWidth: 220
                Repeater {
                    model: App.DeviceContext.devices
                    delegate: Item {
                        Layout.preferredHeight: button.implicitHeight
                        Layout.preferredWidth: 200
                        Layout.alignment: Qt.AlignHCenter
                        readonly property var info: model.info
                        SidebarTabButton {
                            id : button
                            anchors.fill: parent
                            currentSection: model.currentSection
                            title: info.product_type
                            udid: info["UniqueDeviceID"]
                            wireless: info["connection_type"] === "Wireless"
                            onSectionChanged: {
                                if (model.currentSection !== sectionIndex)
                                    model.currentSection = sectionIndex

                                App.DeviceContext.currentDeviceUdid  = info["UniqueDeviceID"]
                            }
                        }
                    }
                }
                // spacer taker
                Item {
                    Layout.fillHeight : true
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
        }


        Welcome {
            id: welcomePage
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

}
