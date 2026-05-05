import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import com.kdab.cxx_qt.demo 1.0

Item {
    id: root
    property ListModel devices: ListModel {}
    property string currentDeviceUdid : ""
    // default info section
    property int currentSection : 0 

    property bool showWelcomePage : true
    readonly property Core core: Core {}

    Component.onCompleted: {
        root.core.init()
    }

    Connections {
        target: root.core

        function onDevice_event(eventType, udid, info) {
            console.log("Device event:", eventType, udid, JSON.stringify(info))
            if (eventType === 1) {
                devices.append({ udid: udid, info: info })
                root.showWelcomePage = false
                root.currentDeviceUdid = udid
            }
        }
    }

    // Connections {
    //     target : NetworkDeviceProvider

    RowLayout {
        anchors.fill: parent
        spacing: 10
        // Layout.fillWidth : true
        // Layout.fillHeight : true
        
        ColumnLayout {
            Layout.fillWidth : true
            Layout.fillHeight : true
            Layout.preferredWidth: 220
            Repeater {
                model: devices
                delegate: Item {
                    SidebarTabButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 220
                        Layout.preferredHeight: 40
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
                
        }



        Repeater {
            model: devices
            delegate:Item {
                Layout.fillWidth : true
                Layout.fillHeight : true
                visible : model.udid === root.currentDeviceUdid 
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
        visible : showWelcomePage
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

}
