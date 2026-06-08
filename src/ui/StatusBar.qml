import QtQuick
import QtQuick.Controls 
import QtQuick.Layouts 
import "." as App

Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 28
    
    RowLayout {
        anchors.fill: parent
        spacing: 12
        Label {
            text : qsTr("iDescriptor: %1 device(s) connected").arg(App.DeviceContext.devices.count)
            color: "red"
        }
        Button {
            icon.source: "qrc:/resources/icons/lets-icons_horizontal-down-left-main-light.svg"
            onClicked: {
                App.DeviceContext.showWelcomePage = !App.DeviceContext.showWelcomePage
            }
            background: Rectangle {
                color: "transparent"
            }
        }
        Button {
            id: myButton
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