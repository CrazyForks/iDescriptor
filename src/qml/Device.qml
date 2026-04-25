import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "."
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
            console.log("Device event:", eventType, udid, info)
            root.showWelcomePage = false;
            if (eventType === 1) {
                // Use append to add items to the ListModel
                devices.append({ udid: udid, info: info })
            }
        }
    }

    Repeater {
        model: devices
        delegate: Label {
            text: model.info
            font.pixelSize: 16
            padding: 10
            Layout.fillWidth: true
            //MouseArea {
            //    anchors.fill: parent
            //    onClicked: {
            //        root.currentIndex = index + 1
            //        root.showWelcomePage = false
            //   }
            //}
        }
    }


    Welcome {
        id: welcomePage
        visible : showWelcomePage
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

}
