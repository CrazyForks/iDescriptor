import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import "." as App

Button {
    id: root

    required property string iconSource
    property bool selected: false

    signal destinationRequested

    Layout.fillWidth: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    Layout.preferredHeight: App.Theme.sidebarRowHeight
    hoverEnabled: true
    leftPadding: 10
    rightPadding: 10
    topPadding: 0
    bottomPadding: 0
    onClicked: root.destinationRequested()

    background: Rectangle {
        radius: App.Theme.sidebarCornerRadius
        color: root.selected ? App.Theme.sidebarSelection
                             : root.down ? App.Theme.pressed
                                         : root.hovered ? App.Theme.hover
                                                        : "transparent"

        Behavior on color {
            ColorAnimation { duration: App.Theme.fastAnimation }
        }
    }

    contentItem: RowLayout {
        spacing: 8

        IconImage {
            source: root.iconSource
            color: root.selected ? App.Theme.selection : App.Theme.icon
            sourceSize.width: App.Theme.sidebarIconSize
            sourceSize.height: App.Theme.sidebarIconSize
            Layout.preferredWidth: App.Theme.sidebarIconSize
            Layout.preferredHeight: App.Theme.sidebarIconSize
            opacity: root.selected ? 1 : 0.82
        }

        Label {
            Layout.fillWidth: true
            text: root.text
            color: App.Theme.text
            font.pixelSize: 13
            elide: Text.ElideRight
        }
    }
}
