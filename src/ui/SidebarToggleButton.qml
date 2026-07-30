import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import "." as App

Button {
    id: root
    flat: true

    // implicitWidth: 30
    // implicitHeight: 30
    hoverEnabled: true

    // Layout.topMargin: Qt.platform.os === "windows" ? 990 : 0

    ToolTip.visible: hovered
    ToolTip.delay: 500
    ToolTip.text: qsTr("Toggle sidebar")

    background: Rectangle {
        radius: 6
        color: root.down ? App.Theme.pressed : root.hovered ? App.Theme.hover : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: App.Theme.fastAnimation
            }
        }
    }

    contentItem: IconImage {
        source: "qrc:/resources/icons/sidebar_left.svg"
        color: App.Theme.icon
        sourceSize.width: App.Theme.sidebarIconSize
        sourceSize.height: App.Theme.sidebarIconSize
        width: App.Theme.sidebarIconSize
        height: App.Theme.sidebarIconSize
    }
}
