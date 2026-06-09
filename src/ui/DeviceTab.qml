import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import iDescriptor 1.0
import "." as App
// FIXME: this will fail on Linux and macOS
import "./windows"

Item {
    id: root
    // default info section
    property int currentSection : 0

    Component.onCompleted: {
        App.DeviceContext.init()
    }

    StackLayout {
        anchors.fill: parent
        currentIndex:  App.DeviceContext.showWelcomePage ? 1 : 0

        RowLayout {
            anchors.fill: parent
            spacing: 0
            
            ColumnLayout {
                Layout.fillHeight : true
                Layout.preferredWidth: 220
                Repeater {
                    model: App.DeviceContext.devices
                    delegate: Item {
                        Layout.fillHeight : true
                        // implicitHeight: button.implicitHeight
                        Layout.preferredWidth: 200
                        Layout.alignment: Qt.AlignHCenter
                        readonly property string deviceUdid: model.udid
                        readonly property var info: model.info
                        SidebarTabButton {
                            id : button
                            anchors.fill: parent
                            currentSection: root.currentSection
                            title: info.product_type
                            udid : info["UniqueDeviceID"]
                            onSectionChanged: {
                                if (root.currentSection !== sectionIndex)
                                    root.currentSection = sectionIndex

                            App.DeviceContext.currentDeviceUdid  = deviceUdid                             
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
                        currentSection: root.currentSection
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
