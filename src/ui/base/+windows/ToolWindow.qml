import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".." as App
import "./"

DefaultWindow {
    id: root
    required property string udid
    required property var device
    property bool auto_close: true

    Connections {
        target: App.DeviceContext
        enabled: root.auto_close

        function onDeviceRemoved(removedUdid) {
            if (root.udid === removedUdid)
                root.close()
        }
    }
}
