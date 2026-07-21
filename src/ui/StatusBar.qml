import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App
import "./base"

Item {
    id: root
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
            text : App.DeviceContext.getDeviceCount() ? qsTr("iDescriptor: %1 device(s) connected").arg(App.DeviceContext.getDeviceCount()) : qsTr("iDescriptor: no devices")
        }
        IconToolButton {
            id: myButton
            icon.source: "qrc:/resources/icons/uim_process.svg"
            onClicked: {
                var globalPos = myButton.mapToGlobal(0, 0)
               
                StatusWindow.toggle(Window.window, globalPos, myButton.width, myButton.height)
            }
        }
        IconToolButton {
            id: welcomeButton
            visible: App.DeviceContext.currentTab === 0
            icon.source: "qrc:/resources/icons/lets-icons_horizontal-down-left-main-light.svg"
            onClicked: {
                App.DeviceContext.showWelcomePage = !App.DeviceContext.showWelcomePage
            }
        }
        
        Item { Layout.fillWidth: true }

        IconToolButton {
            id: settingsButton
            icon.source: "qrc:/resources/icons/mingcute_settings-7-line.svg"
            onClicked: App.Settings.open()
        }
        
    }

    Component.onCompleted: StatusWindow.registerStatusBarOpener(Window.window, myButton)
    Component.onDestruction: StatusWindow.unregisterStatusBarOpener(myButton)
}
