import QtQuick 2.15
import QtQuick.Controls 2.15
import FluentUI 1.0
import QtQuick.Layouts 1.15
import "."

FluWindow {

    id:window
    title: "iDescriptor"
    width: 1000
    height: 668 
    minimumWidth: 668
    minimumHeight: 320
    launchMode: FluWindowType.SingleTask
    fitsAppBarWindows: true
    property int currentIndex: 0

    appBar: FluAppBar {
        height: 28
        showDark: true
        z: 7

        RowLayout{
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 10
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
    }


    Tabs {
        currentIndex: window.currentIndex
        anchors.fill: parent
        anchors.topMargin: appBar.height
    }
}
