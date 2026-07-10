import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".." as App
import FluentUI

FluWindow {
    id: root
    required property string udid
    required property var device
    property bool auto_close: true

    launchMode: FluWindowType.Standard 
    Component.onCompleted : {
        if (settingsManager.window_effect() === "acrylic") {
            root.backgroundColor = "transparent"
            root.effect = "acrylic"
        } else {
            root.effect = "normal"
        }

        if (root.auto_close) {
            App.DeviceContext.deviceRemoved.connect((udid) => {
                if (root.udid === udid) {root.close()}
            })
        }
    }
}
