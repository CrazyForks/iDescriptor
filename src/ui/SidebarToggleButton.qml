import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import "." as App

ToolButton {
    id: root

    implicitWidth: 30
    implicitHeight: 30
    hoverEnabled: true

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
        sourceSize.width: 19
        sourceSize.height: 19
    }
}
