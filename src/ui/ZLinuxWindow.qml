import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Window
import "."

ApplicationWindow {
    id: window
    title: qsTr("iDescriptor")
    width: 1000
    height: 668
    minimumWidth: 900
    minimumHeight: 550
    visible: true
    color: "transparent"
    palette: Theme.palette
    flags: Qt.Window | Qt.FramelessWindowHint
    topPadding: 0
    leftPadding: 0
    rightPadding: 0
    bottomPadding: 0

    readonly property bool maximized: visibility === Window.Maximized
    readonly property int resizeBorderWidth: 6
    readonly property int resizeCornerSize: 12

    Component.onCompleted: {
        Updater.checkAutomatically()
    }

    onClosing: function(close) {
        ClosingHandler.handler("*", close, window)
    }

    Rectangle {
        id: windowSurface
        anchors.fill: parent
        color: Theme.windowBackground
        radius: window.maximized ? 0 : 10
        clip: !window.maximized

        MainWorkspace {
            anchors.fill: parent
        }

        // Use the compositor's native move operation so snapping and tiling remain available.
        MouseArea {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: closeButton.left
            height: 20
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeAllCursor
            z: 1000

            onPressed: function(mouse) {
                window.startSystemMove()
                mouse.accepted = false
            }
        }

        Button {
            id: closeButton
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 10
            anchors.rightMargin: 10
            width: 24
            height: 24
            padding: 0
            z: 1001
            hoverEnabled: true
            Accessible.name: qsTr("Close")
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Close")
            onClicked: window.close()

            background: Rectangle {
                radius: width / 2
                color: closeButton.down
                       ? (Theme.darkMode ? "#5e5c64" : "#c0bfbc")
                       : closeButton.hovered
                         ? (Theme.darkMode ? "#4a484f" : "#deddda")
                         : (Theme.darkMode ? "#3d3b40" : "#e6e5e3")
                border.width: 1
                border.color: Theme.darkMode ? "#5e5c64" : "#c0bfbc"
            }

            contentItem: IconImage {
                source: "qrc:/resources/icons/material-symbols_close-rounded.svg"
                sourceSize.width: 16
                sourceSize.height: 16
                width: 16
                height: 16
                color: Theme.text
            }
        }

        // Delegate resizing to the window manager for native behavior on X11 and Wayland.
        MouseArea {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: window.resizeCornerSize
            anchors.rightMargin: window.resizeCornerSize
            height: window.resizeBorderWidth
            enabled: !window.maximized
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeVerCursor
            z: 1100
            onPressed: window.startSystemResize(Qt.TopEdge)
        }

        MouseArea {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: window.resizeCornerSize
            anchors.rightMargin: window.resizeCornerSize
            height: window.resizeBorderWidth
            enabled: !window.maximized
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeVerCursor
            z: 1100
            onPressed: window.startSystemResize(Qt.BottomEdge)
        }

        MouseArea {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.topMargin: window.resizeCornerSize
            anchors.bottomMargin: window.resizeCornerSize
            width: window.resizeBorderWidth
            enabled: !window.maximized
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeHorCursor
            z: 1100
            onPressed: window.startSystemResize(Qt.LeftEdge)
        }

        MouseArea {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.topMargin: window.resizeCornerSize
            anchors.bottomMargin: window.resizeCornerSize
            width: window.resizeBorderWidth
            enabled: !window.maximized
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeHorCursor
            z: 1100
            onPressed: window.startSystemResize(Qt.RightEdge)
        }

        MouseArea {
            anchors.top: parent.top
            anchors.left: parent.left
            width: window.resizeCornerSize
            height: window.resizeCornerSize
            enabled: !window.maximized
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeFDiagCursor
            z: 1101
            onPressed: window.startSystemResize(Qt.TopEdge | Qt.LeftEdge)
        }

        MouseArea {
            anchors.top: parent.top
            anchors.right: parent.right
            width: window.resizeCornerSize
            height: window.resizeCornerSize
            enabled: !window.maximized
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeBDiagCursor
            z: 1101
            onPressed: window.startSystemResize(Qt.TopEdge | Qt.RightEdge)
        }

        MouseArea {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: window.resizeCornerSize
            height: window.resizeCornerSize
            enabled: !window.maximized
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeBDiagCursor
            z: 1101
            onPressed: window.startSystemResize(Qt.BottomEdge | Qt.LeftEdge)
        }

        MouseArea {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: window.resizeCornerSize
            height: window.resizeCornerSize
            enabled: !window.maximized
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeFDiagCursor
            z: 1101
            onPressed: window.startSystemResize(Qt.BottomEdge | Qt.RightEdge)
        }
    }
}
