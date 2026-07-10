import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../" as App

Dialog {

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: App.Theme.mediumAnimation; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: App.Theme.mediumAnimation; easing.type: Easing.OutCubic }
        }
    }

    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: App.Theme.fastAnimation; easing.type: Easing.InCubic }
            NumberAnimation { property: "scale"; from: 1; to: 0.98; duration: App.Theme.fastAnimation; easing.type: Easing.InCubic }
        }
    }

    background: Item {
        implicitWidth: root.width
        implicitHeight: panel.implicitHeight

        DropShadow {
            anchors.fill: panel
            source: panel
            radius: 24
            samples: 32
            horizontalOffset: 0
            verticalOffset: 10
            color: App.Theme.darkMode ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.18)
            // color: App.Theme.softBg
            // color: palette.window
            transparentBorder: true
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: 16
            // color: App.Theme.darkMode ? Qt.rgba(0.12, 0.12, 0.13, 0.96) : Qt.rgba(1, 1, 1, 0.96)
            color: palette.window
            border.color: App.Theme.softBgBorder
            border.width: 1
        }
    }
}