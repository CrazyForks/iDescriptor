import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

ApplicationWindow {
    id: window
    title: qsTr("iDescriptor")
    width: 1000
    height: 668
    minimumWidth: 668
    minimumHeight: 320
    visible: true

    Component.onCompleted: {
        Updater.checkAutomatically()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            spacing: 0
            TabButton {
                text: qsTr("iDevice")
                onClicked: DeviceContext.currentTab = 0
                active: DeviceContext.currentTab == 0
            }

            TabButton {
                text: qsTr("Apps")
                onClicked: DeviceContext.currentTab = 1
                active: DeviceContext.currentTab == 1
            }
            TabButton {
                text: qsTr("Toolbox")
                onClicked: DeviceContext.currentTab = 2
                active: DeviceContext.currentTab == 2
            }
            TabButton {
                text: qsTr("Jailbroken")
                onClicked: DeviceContext.currentTab = 3
                active: DeviceContext.currentTab == 3
            }
        }

        Tabs {
            currentIndex: DeviceContext.currentTab
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        StatusBar {}
    }
}
