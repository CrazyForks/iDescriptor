import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import com.kdab.cxx_qt.demo 1.0

Item {
    id: root
    property ListModel devices: ListModel {}

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
                root.showWelcomePage = false;
                devices.append({ udid: udid, info: info })
            }
        }
    }

    Repeater {
        model: devices
        delegate: Device {
            udid: model.udid
            anchors.fill: parent
            info: model.info
        }
    }


    Welcome {
        id: welcomePage
        visible : showWelcomePage
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

}
