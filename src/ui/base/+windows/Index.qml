import QtQuick 2.15
import QtQuick.Controls 2.15
import FluentUI 1.0
import QtQuick.Layouts 1.15
import ".."

FluWindow {
    id:window
    title: qsTr("iDescriptor")
    width: 1000
    height: 668 
    minimumWidth: 668
    minimumHeight: 320
    launchMode: FluWindowType.SingleTask
    fitsAppBarWindows: true

     Component.onCompleted: {  
        window.effect = "acrylic"
    }  

    appBar: FluAppBar {
        height: 28
        showDark: false
        showStayTop: false
        z: 7

        RowLayout{
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top 
            anchors.topMargin: 10
            anchors.rightMargin: Qt.platform.os === "windows" ? 40 : 0
            
            spacing: 0
            TabButton {
                text: qsTr("iDevice")
                onClicked: DeviceContext.currentTab = 0
                active: DeviceContext.currentTab == 0
            }

            TabButton {
                text: qsTr("Apps")
                onClicked: DeviceContext.currentTab = 1
                active:  DeviceContext.currentTab == 1
            }
            TabButton {
                text: qsTr("Toolbox")
                onClicked:  DeviceContext.currentTab = 2
                active:  DeviceContext.currentTab == 2
            }
            TabButton {
                text: qsTr("Jailbroken")
                onClicked:  DeviceContext.currentTab = 3
                active:  DeviceContext.currentTab == 3
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: appBar.height + 30
        Tabs {
            Layout.fillWidth : true
            Layout.fillHeight : true
            
            currentIndex: DeviceContext.currentTab
        }

        StatusBar {
            
        }
    }

}
