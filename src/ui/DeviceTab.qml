import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import iDescriptor 1.0
import "." as App

Item {
    id: root
    // default info section
    property int currentSection : 2

    Component.onCompleted: {
        App.DeviceContext.init()
    }


    RowLayout {
        anchors.fill: parent
        spacing: 10
        // Layout.fillWidth : true
        // Layout.fillHeight : true
        
        ColumnLayout {
            // Layout.fillWidth : true
            Layout.fillHeight : true
            Layout.preferredWidth: 220
            Repeater {
                model: App.DeviceContext.devices
                delegate:SidebarTabButton {
                        Layout.fillHeight : true
                        Layout.preferredWidth: 200
                        Layout.alignment: Qt.AlignHCenter
                        currentSection: root.currentSection 
                        // udid: model.udid
               
                        // anchors.fill: parent
                        // info: model.info 
                        onSectionChanged: {
                            console.log("sectionIndex", sectionIndex)
                            // if (root.currentDeviceUdid  !== udid) 
                            //     root.currentDeviceUdid  = udid
                            if (root.currentSection !== sectionIndex)
                                root.currentSection = sectionIndex
                    }
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
        visible : App.DeviceContext.showWelcomePage
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

}
