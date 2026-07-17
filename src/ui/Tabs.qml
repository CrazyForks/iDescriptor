import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./base"

Item {
    id: root
    required property int currentIndex

    StackLayout {
        anchors.fill: parent
        currentIndex: root.currentIndex

        /*
            let's not lazy load the main device tab
            this way it's a bit faster to show the device
        */
        AnimatedTab {
            index: 0
            currentIndex : root.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true
            DeviceTab {
                anchors.fill: parent
            }
        }

        Loader {
            active: root.currentIndex === 1 || item
            sourceComponent: appsTabComponent
        }

        AnimatedTab {
            index: 2
            currentIndex: root.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true

            Component.onCompleted: {
                Toolbox.parent = this
                Toolbox.anchors.fill = this
            }
        }

        Loader {
            active: root.currentIndex === 3 || item
            sourceComponent: jailbreakTabComponent
        }
    }


    Component {
        id: appsTabComponent
        AnimatedTab {
            index: 1
            currentIndex : root.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true
            AppsTab {
                anchors.fill: parent
            }
        }
    }


    Component {
        id: jailbreakTabComponent
        AnimatedTab {
            index: 3
            currentIndex: root.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true

            Jailbroken {
                anchors.fill: parent
            }
        }
    }
}
