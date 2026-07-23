import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import "../"

ToolButton {
    id: root

    property string toolTipText: ""
    property int iconSize: 18

    padding: 0
    implicitWidth: 32
    implicitHeight: 32
    display: AbstractButton.IconOnly
    icon.width: iconSize
    icon.height: iconSize
    icon.color: enabled ? palette.text : Theme.textMuted

    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: root.down ? 0.90 : 1.0
        yScale: root.down ? 0.90 : 1.0

        Behavior on xScale {
            NumberAnimation {
                duration: Theme.fastAnimation
                easing.type: Easing.OutCubic
            }
        }

        Behavior on yScale {
            NumberAnimation {
                duration: Theme.fastAnimation
                easing.type: Easing.OutCubic
            }
        }
    }

    HoverHandler {
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    contentItem: Item {
        IconImage {
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            source: root.icon.source
            sourceSize.width: root.iconSize
            sourceSize.height: root.iconSize
            color: root.enabled ? root.palette.text : Theme.textMuted
            opacity: root.enabled ? 1.0 : 0.55
        }
    }

    background: Rectangle {
        radius: 7
        color: !root.enabled
               ? "transparent"
               : root.down
                 ? Theme.pressed
                 : root.hovered
                   ? Theme.hover
                   : "transparent"
        border.color: root.activeFocus ? Theme.focus : "transparent"
        border.width: 1

        Behavior on color {
            ColorAnimation { duration: Theme.fastAnimation }
        }
    }

    ToolTip.visible: hovered && toolTipText.length > 0
    ToolTip.delay: 400
    ToolTip.text: toolTipText
}
