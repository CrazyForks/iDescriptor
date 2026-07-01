import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".." as App
import FluentUI

FluWindow {
    id: root
    required property string udid
    required property var device
    property bool auto_close: true
    launchMode: FluWindowType.Standard 
    Component.onCompleted : {
        root.effect = "acrylic"

        if (root.auto_close) {
            App.DeviceContext.deviceRemoved.connect((udid) => {
                if (root.udid === udid) {root.close()}
            })
        }
    }
}
