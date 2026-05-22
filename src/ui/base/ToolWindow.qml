import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".." as App


Window {
    id: root
    required property string udid
    required property var device
    Component.onCompleted : {
        App.DeviceContext.device_removed.connect((udid) => {
            if (root.udid === udid) {root.close()}
        })
    }
}