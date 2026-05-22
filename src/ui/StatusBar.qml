import QtQuick
import QtQuick.Controls 
import QtQuick.Layouts 
import "." as App

Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 28
    Label {
        text : qsTr("iDescriptor: %1 device(s) connected").arg(App.DeviceContext.devices.count)
        color: "red"
    }
}