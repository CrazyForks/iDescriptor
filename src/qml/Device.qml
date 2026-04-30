import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property var info: ({})
    property var udid: "" 
    DeviceGallery {
        visible : true
        anchors.fill: parent
        udid: root.udid
        // info: root.info
    }

    DeviceInfo {
        anchors.fill: parent
        visible : false
        info: root.info
    }

}