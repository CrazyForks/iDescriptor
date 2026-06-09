import QtQuick
import QtQuick.Controls 
import QtQuick.Layouts 
import "." as App

Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 28

    Layout.leftMargin: 10
    Layout.rightMargin: 10
    Layout.topMargin: 5
    Layout.bottomMargin: 5
    
    RowLayout {
        anchors.fill: parent
        spacing: Qt.platform.os === "windows" ? 2 : 5
        Label {
            text : qsTr("iDescriptor: %1 device(s) connected").arg(App.DeviceContext.devices.count)
        }
        Button {
            visible: App.DeviceContext.currentTab === 0
            icon.source: "qrc:/resources/icons/lets-icons_horizontal-down-left-main-light.svg"
            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }
            onClicked: {
                App.DeviceContext.showWelcomePage = !App.DeviceContext.showWelcomePage
            }
            background: Rectangle {
                color: "transparent"
            }
        }
        Button {
            id: myButton
            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }
            icon.source: "qrc:/resources/icons/uim_process.svg"
            onClicked: {
                var globalPos = myButton.mapToGlobal(0, 0)
               
                StatusWindow.toggle(Window.window,globalPos)
            }
            background: Rectangle {
                color: "transparent"
            }
        }
        
        Item { Layout.fillWidth: true }
        
    }
}