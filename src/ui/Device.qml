import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property var info: ({})
    property var udid: "" 
    required property int currentSection
    

    DeviceInfo {
        anchors.fill: parent
        visible : currentSection == 0
        info: root.info
    }

    DeviceGallery {
        visible : currentSection == 2
        anchors.fill: parent
        udid: root.udid
        // info: root.info
    }

    FilesSection {
        visible : currentSection == 3
        udid : root.udid
    }
}