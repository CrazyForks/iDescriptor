import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "./base"

Item {
    id: root
    required property int currentIndex


    AnimatedTab {
        index: 0
        currentIndex : root.currentIndex
        DeviceTab {
            anchors.fill: parent
        }
    }

    AnimatedTab {
        index: 1
        currentIndex : root.currentIndex
        AppsTab {
            anchors.fill: parent
        }
    }

    AnimatedTab {
        index: 2
        currentIndex : root.currentIndex
        Toolbox {
            anchors.fill: parent
        }
    }

}
