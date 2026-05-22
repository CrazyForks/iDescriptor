import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "."

ApplicationWindow {

    id:window
    title: "iDescriptor"
    width: 1000
    height: 668 
    minimumWidth: 668
    minimumHeight: 320
    visible: true
    property int currentIndex: 0

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            spacing: 0
            TabButton {
                text: qsTr("iDevice")
                onClicked: currentIndex = 0 
                active: currentIndex == 0
            }

            TabButton {
                text: qsTr("Apps")
                onClicked: currentIndex = 1
                active: currentIndex == 1
            }
            TabButton {
                text: qsTr("Toolbox")
                onClicked: currentIndex = 2
                active: currentIndex == 2
            }
            TabButton {
                text: qsTr("Jailbroken")
                onClicked: currentIndex = 3
                active: currentIndex == 3
            }
        }


        Tabs {
            currentIndex: window.currentIndex
            Layout.fillWidth : true
            Layout.fillHeight : true
        }

        StatusBar {
            
        }
    }
}
