import QtQuick
import QtQuick.Controls
import "../"

ToolButton {
    id: root

    padding: 0
    display: AbstractButton.IconOnly
    icon.color: Theme.icon

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    background: Rectangle {
        radius: 4
        color: root.down ? Theme.pressed : (root.hovered ? Theme.hover : "transparent")
    }
}
