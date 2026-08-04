pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "./base"

Item {
    id: root
    required property string currentDestination
    readonly property int currentIndex: root.destinationIndex(currentDestination)

    function destinationIndex(destination) {
        switch (destination) {
        case "device":
        case "pendingDevice":
        case "recoveryDevice":
            return 0
        case "apps":
            return 1
        case "toolbox":
            return 2
        case "jailbroken":
            return 3
        case "community":
            return 5
        case "donate":
            return 6
        case "welcome":
        default:
            return 4
        }
    }

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

        AnimatedTab {
            index: 4
            currentIndex: root.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true

            Welcome {
                anchors.fill: parent
            }
        }

        AnimatedTab {
            index: 5
            currentIndex: root.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true

            Community {
                anchors.fill: parent
            }
        }

        AnimatedTab {
            index: 6
            currentIndex: root.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true

            Donate {
                anchors.fill: parent
            }
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
