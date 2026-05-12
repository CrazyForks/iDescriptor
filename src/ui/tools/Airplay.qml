import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Window

import iDescriptor 1.0
import org.freedesktop.gstreamer.Qt6GLVideoItem 1.0

Window {
    id: win
    width: 900
    height: 600
    visible: true

    Component.onCompleted: {
        Qt.callLater(() => {
            AirplayImp.init(video)
        })
    }

    GstGLQt6VideoItem {
        id: video
        anchors.fill: parent
        objectName: "videoItem"
        z: 99
    }

    Rectangle {
        color: Qt.rgba(1, 1, 1, 0.7)
        border.width: 1
        border.color: "white"
        anchors.bottom: video.bottom
        anchors.bottomMargin: 15
        anchors.horizontalCenter: parent.horizontalCenter
        width : parent.width - 30
        height: parent.height - 30
        radius: 8

        MouseArea {
            id: mousearea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                parent.opacity = 1.0
                hidetimer.start()
            }
        }

        Timer {
            id: hidetimer
            interval: 5000
            onTriggered: {
                parent.opacity = 0.0
                stop()
            }
        }
    }
}