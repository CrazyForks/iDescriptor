import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".." as App


Window {
    id: root
    required property string udid
    required property var device
    property bool auto_close: true
    color: palette.window

    Component.onCompleted : {
        if (Qt.platform.os === "osx") {
            QmlUtils.setup_tool_window(root.contentItem.Window.window)
        }

        if (root.auto_close) {
            App.DeviceContext.deviceRemoved.connect((udid) => {
                if (root.udid === udid) {root.close()}
            })
        }
    }
}
