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

    Component.onCompleted : {
        if (root.auto_close) {
            App.DeviceContext.deviceRemoved.connect((udid) => {
                if (root.udid === udid) {root.close()}
            })
        }
    }
}
