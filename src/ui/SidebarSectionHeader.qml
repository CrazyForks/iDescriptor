import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import "." as App

Button {
    id: root

    property bool expanded: true

    signal toggleRequested

    Layout.fillWidth: true
    Layout.leftMargin: 4
    Layout.rightMargin: 8
    Layout.preferredHeight: 26
    hoverEnabled: true
    leftPadding: 4
    rightPadding: 4
    topPadding: 0
    bottomPadding: 0
    onClicked: root.toggleRequested()

    background: Rectangle {
        color: "transparent"

        HoverHandler {
            id: headerHover
        }
    }

    contentItem: RowLayout {
        spacing: 4

        Label {
            Layout.fillWidth: true
            text: root.text
            color: App.Theme.textMuted
            font.pixelSize: 11
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        IconImage {
            source: "qrc:/resources/icons/material-symbols_keyboard-arrow-down.svg"
            color: palette.text
            sourceSize.width: 14
            sourceSize.height: 14
            Layout.preferredWidth: 14
            Layout.preferredHeight: 14
            opacity: headerHover.hovered ? 0.82 : 0
            rotation: root.expanded ? 0 : -90

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.InOutQuad
                }
            }

            Behavior on rotation {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

}
