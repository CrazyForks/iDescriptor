import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
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
            DeviceTab {
                anchors.fill: parent
            }
        }

        Loader {
            active: root.currentIndex === 1 || item
            sourceComponent: appsTabComponent
        }

        Loader {
            active: root.currentIndex === 2 || item
            sourceComponent: toolboxTabComponent
        }
    }


    Component {
        id: appsTabComponent
        AnimatedTab {
            index: 1
            currentIndex : root.currentIndex
            AppsTab {
                anchors.fill: parent 
            }
        }
    }

    Component {
        id: toolboxTabComponent
        AnimatedTab {
            index: 2
            currentIndex : root.currentIndex
            Toolbox {
                anchors.fill: parent
            }
        }
     }


}
