import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import QtQuick.Window
import "." as App

Window {
    required property string filePath
    property int thumbVersion: 0
    required property string udid
    property var afcClient: null
    property int row : 999999
    property string streamUrl: ""
    property string errorMessage: ""
    property bool streamReleased: true
    readonly property bool isVideo: App.Helpers.is_video_file(filePath)
    id: root
    visible: true   
    width: Screen.width
    height: Screen.height
    visibility: Window.FullScreen
    
    color: "black"

    function startVideoStream() {
        if (!isVideo)
            return

        if (!afcClient || typeof afcClient.start_video_stream !== "function") {
            errorMessage = qsTr("AFC client is not available.")
            return
        }

        var url = afcClient.start_video_stream(filePath)
        if (!url || url.length === 0) {
            errorMessage = qsTr("Failed to start stream.")
            return
        }

        streamUrl = url
        streamReleased = false
        player.source = streamUrl
        player.play()
    }

    function cleanupVideoStream() {
        if (streamReleased || streamUrl.length === 0)
            return

        player.stop()

        if (afcClient && typeof afcClient.release_video_stream === "function")
            afcClient.release_video_stream(streamUrl)

        streamReleased = true
        streamUrl = ""
    }

    Component.onCompleted: startVideoStream()
    Component.onDestruction: cleanupVideoStream()
    onClosing: cleanupVideoStream()

    Connections {
        target: imageLoader 

        function onThumbnailReady(path,rowHint) {
            if (path == root.filePath && rowHint == root.row) {
                root.thumbVersion++
            }
        }
    }

    Image {
        visible: !root.isVideo
        cache: false
        anchors.fill: parent
        //FIXME:use encodeuricomp
        source: root.isVideo ? "" : "image://thumb/" + filePath + "?udid=" + root.udid + "&index=" + row + "&v=" + thumbVersion
        fillMode: Image.PreserveAspectFit
    }

    MediaPlayer {
        id: player
        audioOutput: AudioOutput {}
        videoOutput: videoOutput
        onErrorOccurred: function(error, message) {
            root.errorMessage = message && message.length > 0 ? message : qsTr("Failed to play video.")
        }
    }

    VideoOutput {
        id: videoOutput
        visible: root.isVideo && root.errorMessage.length === 0
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    Rectangle {
        visible: root.isVideo
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 58
        color: Qt.rgba(0, 0, 0, 0.55)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            Button {
                text: player.playbackState === MediaPlayer.PlayingState ? qsTr("Pause") : qsTr("Play")
                enabled: root.errorMessage.length === 0 && root.streamUrl.length > 0
                onClicked: {
                    if (player.playbackState === MediaPlayer.PlayingState)
                        player.pause()
                    else
                        player.play()
                }
            }

            Slider {
                Layout.fillWidth: true
                enabled: player.duration > 0
                from: 0
                to: Math.max(1, player.duration)
                value: player.position
                onMoved: player.setPosition(value)
            }

            Button {
                text: qsTr("Close")
                onClicked: root.close()
            }
        }
    }

    Text {
        visible: root.errorMessage.length > 0
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 520)
        text: root.errorMessage
        color: "white"
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.pixelSize: 15
    }

    Shortcut {
        sequence: StandardKey.Cancel
        onActivated: root.close()
    }
}
