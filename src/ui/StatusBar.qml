import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as App

Item {
    id: root
    Layout.fillWidth: true
    Layout.preferredHeight: 28
    readonly property int iconSize: 16
    // property int buttonSize: 26

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
        ToolButton {
            id: myButton
            // Layout.preferredWidth: root.buttonSize
            // Layout.preferredHeight: root.buttonSize
            padding: 0
            display: AbstractButton.IconOnly
            icon.source: "qrc:/resources/icons/uim_process.svg"
            icon.color: App.Theme.icon
            icon.width: root.iconSize
            icon.height: root.iconSize
            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }
            onClicked: {
                var globalPos = myButton.mapToGlobal(0, 0)
               
                StatusWindow.toggle(Window.window, globalPos, myButton.width, myButton.height)
            }
            background: Rectangle {
                radius: 4
                color: myButton.down ? App.Theme.pressed : (myButton.hovered ? App.Theme.hover : "transparent")
            }
        }
        ToolButton {
            id: welcomeButton
            visible: App.DeviceContext.currentTab === 0
            // Layout.preferredWidth: root.buttonSize
            // Layout.preferredHeight: root.buttonSize
            padding: 0
            display: AbstractButton.IconOnly
            icon.source: "qrc:/resources/icons/lets-icons_horizontal-down-left-main-light.svg"
            icon.color: App.Theme.icon
            icon.width: root.iconSize
            icon.height: root.iconSize
            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }
            onClicked: {
                App.DeviceContext.showWelcomePage = !App.DeviceContext.showWelcomePage
            }
            background: Rectangle {
                radius: 4
                color: welcomeButton.down ? App.Theme.pressed : (welcomeButton.hovered ? App.Theme.hover : "transparent")
            }
        }
        
        Item { Layout.fillWidth: true }

        ToolButton {
            id: settingsButton
            // Layout.preferredWidth: root.buttonSize
            // Layout.preferredHeight: root.buttonSize
            padding: 0
            display: AbstractButton.IconOnly
            icon.source: "qrc:/resources/icons/mingcute_settings-7-line.svg"
            icon.color: App.Theme.icon
            icon.width: root.iconSize
            icon.height: root.iconSize
            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }
            onClicked: App.Settings.open()
            background: Rectangle {
                radius: 4
                color: settingsButton.down ? App.Theme.pressed : (settingsButton.hovered ? App.Theme.hover : "transparent")
            }
        }
        
    }
}
