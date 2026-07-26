import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import QtMultimedia
import QtQuick.Window
import "." as App
import "./base"

DefaultWindow {
    id: root

    required property string filePath
    required property string udid
    property var afcClient: null
    property bool useAfc2: false
    property int row: 999999
    property int thumbVersion: 0
    property real imageZoom: 1.0
    property string streamUrl: ""
    property string houseArrestImageSource: ""
    property string errorMessage: ""
    property bool streamReleased: true
    property bool destructionScheduled: false

    readonly property bool isVideo: App.Helpers.is_video_file(filePath)
    readonly property bool usesHouseArrest: !!afcClient && !!afcClient.bundle_id
    readonly property string fileName: {
        const parts = root.filePath.split("/")
        return parts.length > 0 ? parts[parts.length - 1] : root.filePath
    }
    readonly property bool imageLoading: !root.isVideo
                                                 && root.errorMessage.length === 0
                                                 && ((root.usesHouseArrest
                                                      && root.houseArrestImageSource.length === 0)
                                                     || previewImage.status === Image.Loading)
    readonly property bool videoLoading: root.isVideo
                                         && root.errorMessage.length === 0
                                         && (root.streamUrl.length === 0
                                             || player.mediaStatus === MediaPlayer.LoadingMedia
                                             || player.mediaStatus === MediaPlayer.BufferingMedia)
    readonly property color chromeSurface: App.Theme.darkMode
                                           ? Qt.rgba(44 / 255, 44 / 255, 46 / 255, 0.9)
                                           : Qt.rgba(1, 1, 1, 0.92)
    readonly property color chromeBorder: App.Theme.darkMode
                                          ? Qt.rgba(1, 1, 1, 0.14)
                                          : Qt.rgba(0, 0, 0, 0.12)

    title: qsTr("%1 — iDescriptor").arg(root.fileName)
    visible: true
    width: Screen.width
    height: Screen.height
    visibility: Window.Maximized
    color: "#0b0b0d"

    function formatDuration(milliseconds) {
        if (!isFinite(milliseconds) || milliseconds < 0)
            return "0:00"

        const totalSeconds = Math.floor(milliseconds / 1000)
        const hours = Math.floor(totalSeconds / 3600)
        const minutes = Math.floor((totalSeconds % 3600) / 60)
        const seconds = totalSeconds % 60
        if (hours > 0)
            return hours + ":" + String(minutes).padStart(2, "0")
                    + ":" + String(seconds).padStart(2, "0")
        return minutes + ":" + String(seconds).padStart(2, "0")
    }

    function startVideoStream() {
        if (!root.isVideo)
            return

        root.errorMessage = ""
        if (!root.afcClient || typeof root.afcClient.start_video_stream !== "function") {
            root.errorMessage = qsTr("AFC client is not available.")
            return
        }

        const url = root.afcClient.start_video_stream(root.filePath)
        if (!url || url.length === 0) {
            root.errorMessage = qsTr("Failed to start the video stream.")
            return
        }

        root.streamUrl = url
        root.streamReleased = false
        player.source = root.streamUrl
        player.play()
    }

    function cleanupVideoStream() {
        if (root.streamReleased || root.streamUrl.length === 0)
            return

        player.stop()
        if (root.afcClient && typeof root.afcClient.release_video_stream === "function")
            root.afcClient.release_video_stream(root.streamUrl)

        root.streamReleased = true
        root.streamUrl = ""
    }

    function loadImage() {
        if (root.isVideo || !root.usesHouseArrest)
            return

        root.houseArrestImageSource = ""
        root.errorMessage = ""
        root.afcClient.file_to_base64_img(root.filePath)
    }

    function retryPreview() {
        root.errorMessage = ""
        if (root.isVideo) {
            root.cleanupVideoStream()
            root.startVideoStream()
        } else if (root.usesHouseArrest) {
            root.loadImage()
        } else {
            root.thumbVersion++
        }
    }

    function togglePlayback() {
        if (player.playbackState === MediaPlayer.PlayingState)
            player.pause()
        else
            player.play()
    }

    Component.onCompleted: {
        root.startVideoStream()
        root.loadImage()
    }
    Component.onDestruction: root.cleanupVideoStream()
    onClosing: function(close) {
        root.cleanupVideoStream()
        if (!root.destructionScheduled) {
            root.destructionScheduled = true
            Qt.callLater(root.destroy)
        }
    }

    Connections {
        target: imageLoader
        enabled: !root.usesHouseArrest

        function onThumbnailReady(path, rowHint, afc2) {
            if (path === root.filePath && rowHint === root.row && afc2 === root.useAfc2)
                root.thumbVersion++
        }
    }

    Connections {
        target: root.afcClient
        enabled: root.usesHouseArrest

        function onFileToBase64ImgReady(path, source) {
            if (path !== root.filePath)
                return

            root.houseArrestImageSource = source
            root.thumbVersion++
        }

        function onFileToBase64ImgFailed(path, error) {
            if (path !== root.filePath)
                return

            root.errorMessage = error || qsTr("Failed to load the image preview.")
        }
    }

    MediaPlayer {
        id: player
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
            id: audioOutput
            volume: volumeSlider.value
        }
        videoOutput: videoOutput
        onErrorOccurred: function(error, message) {
            root.errorMessage = message && message.length > 0
                    ? message
                    : qsTr("Failed to play the video.")
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#17171a" }
            GradientStop { position: 0.55; color: "#0d0d0f" }
            GradientStop { position: 1; color: "#070708" }
        }
    }

    Item {
        id: mediaStage
        anchors.fill: parent
        anchors.topMargin: 92
        anchors.bottomMargin: root.isVideo ? 96 : 78
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        clip: true

        Image {
            id: previewImage
            visible: !root.isVideo && root.errorMessage.length === 0
            cache: false
            asynchronous: true
            anchors.fill: parent
            scale: root.imageZoom
            transformOrigin: Item.Center
            source: {
                const version = root.thumbVersion
                if (root.isVideo)
                    return ""
                if (root.usesHouseArrest)
                    return root.houseArrestImageSource
                return "image://thumb/" + encodeURIComponent(root.filePath)
                        + "?udid=" + encodeURIComponent(root.udid)
                        + "&afc2=" + root.useAfc2
                        + "&index=" + root.row
                        + "&v=" + version
            }
            fillMode: Image.PreserveAspectFit

            onStatusChanged: {
                if (status === Image.Error && source.toString().length > 0)
                    root.errorMessage = qsTr("The image could not be displayed.")
            }
        }

        WheelHandler {
            enabled: !root.isVideo && root.errorMessage.length === 0
            target: null
            onWheel: function(event) {
                const step = event.angleDelta.y > 0 ? 0.15 : -0.15
                root.imageZoom = Math.max(0.5, Math.min(4, root.imageZoom + step))
                event.accepted = true
            }
        }

        VideoOutput {
            id: videoOutput
            visible: root.isVideo && root.errorMessage.length === 0
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectFit
        }

        BusyIndicator {
            anchors.centerIn: parent
            visible: root.imageLoading || root.videoLoading
            running: visible
            implicitWidth: 44
            implicitHeight: 44
        }

        Rectangle {
            visible: root.errorMessage.length > 0
            anchors.centerIn: parent
            width: Math.min(460, parent.width - 40)
            height: errorContent.implicitHeight + 48
            radius: 18
            color: root.chromeSurface
            border.color: root.chromeBorder
            border.width: 1

            ColumnLayout {
                id: errorContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 24
                spacing: 12

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    radius: 24
                    color: Qt.rgba(App.Theme.systemRed.r, App.Theme.systemRed.g,
                                   App.Theme.systemRed.b, 0.14)

                    Label {
                        anchors.centerIn: parent
                        text: "!"
                        color: App.Theme.systemRed
                        font.pixelSize: 24
                        font.bold: true
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Preview unavailable")
                    color: App.Theme.text
                    font.pixelSize: 17
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Label {
                    Layout.fillWidth: true
                    text: root.errorMessage
                    color: App.Theme.textMuted
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Button {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Try Again")
                    highlighted: true
                    onClicked: root.retryPreview()
                }
            }
        }
    }

    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.topMargin: 18
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 40, 920)
        height: 62
        radius: 18
        color: root.chromeSurface
        border.color: root.chromeBorder
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 10
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 28
                radius: 9
                color: App.Theme.selectionSoft
                border.color: App.Theme.selectionStroke
                border.width: 1

                Label {
                    anchors.centerIn: parent
                    text: root.isVideo ? qsTr("VIDEO") : qsTr("IMAGE")
                    color: App.Theme.accent
                    font.pixelSize: 10
                    font.bold: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    text: root.fileName
                    color: App.Theme.text
                    font.pixelSize: 14
                    font.bold: true
                    elide: Text.ElideMiddle
                }

                Label {
                    Layout.fillWidth: true
                    text: root.filePath
                    color: App.Theme.textMuted
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                }
            }

            RoundButton {
                symbol: "×"
                tooltip: qsTr("Close Preview")
                onClicked: root.close()
            }
        }
    }

    Rectangle {
        visible: !root.isVideo && root.errorMessage.length === 0
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        anchors.horizontalCenter: parent.horizontalCenter
        width: imageControls.implicitWidth + 24
        height: 46
        radius: 16
        color: root.chromeSurface
        border.color: root.chromeBorder
        border.width: 1

        RowLayout {
            id: imageControls
            anchors.centerIn: parent
            spacing: 4

            RoundButton {
                symbol: "−"
                tooltip: qsTr("Zoom Out")
                enabled: root.imageZoom > 0.5
                onClicked: root.imageZoom = Math.max(0.5, root.imageZoom - 0.25)
            }

            Label {
                Layout.preferredWidth: 52
                text: qsTr("%1%").arg(Math.round(root.imageZoom * 100))
                color: App.Theme.text
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
            }

            RoundButton {
                symbol: "+"
                tooltip: qsTr("Zoom In")
                enabled: root.imageZoom < 4
                onClicked: root.imageZoom = Math.min(4, root.imageZoom + 0.25)
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 20
                color: App.Theme.separator
            }

            Button {
                flat: true
                text: qsTr("Fit")
                font.pixelSize: 12
                onClicked: root.imageZoom = 1
            }
        }
    }

    Rectangle {
        visible: root.isVideo && root.errorMessage.length === 0
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 40, 820)
        height: 62
        radius: 18
        color: root.chromeSurface
        border.color: root.chromeBorder
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 14
            spacing: 10

            RoundButton {
                symbol: player.playbackState === MediaPlayer.PlayingState ? "Ⅱ" : "▶"
                tooltip: player.playbackState === MediaPlayer.PlayingState
                         ? qsTr("Pause") : qsTr("Play")
                enabled: root.streamUrl.length > 0
                onClicked: root.togglePlayback()
            }

            Label {
                Layout.preferredWidth: 46
                text: root.formatDuration(player.position)
                color: App.Theme.textMuted
                font.pixelSize: 11
                horizontalAlignment: Text.AlignRight
            }

            Slider {
                id: positionSlider
                Layout.fillWidth: true
                enabled: player.duration > 0
                from: 0
                to: Math.max(1, player.duration)
                value: player.position
                onMoved: player.setPosition(value)
            }

            Label {
                Layout.preferredWidth: 46
                text: root.formatDuration(player.duration)
                color: App.Theme.textMuted
                font.pixelSize: 11
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 22
                color: App.Theme.separator
            }

            Button {
                id: muteButton
                flat: true
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36

                contentItem: IconImage {
                    source: audioOutput.muted
                            ? "qrc:/resources/icons/material-symbols_volume-off.svg"
                            : "qrc:/resources/icons/material-symbols_volume-mute.svg"
                    color: palette.text
                    sourceSize.width: 20
                    sourceSize.height: 20
                }

                ToolTip.visible: hovered
                ToolTip.text: audioOutput.muted ? qsTr("Unmute") : qsTr("Mute")
                onClicked: audioOutput.muted = !audioOutput.muted
            }

            Slider {
                id: volumeSlider
                Layout.preferredWidth: 88
                from: 0
                to: 1
                value: 0.8
            }
        }
    }

    component RoundButton: Button {
        id: control
        property string symbol: ""
        property string tooltip: ""

        Layout.preferredWidth: 36
        Layout.preferredHeight: 36
        flat: true

        contentItem: Label {
            text: control.symbol
            color: control.enabled ? App.Theme.text : App.Theme.textMuted
            font.pixelSize: 18
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            radius: 10
            color: control.down ? App.Theme.pressed
                  : control.hovered ? App.Theme.hover
                  : "transparent"
        }

        ToolTip.visible: control.hovered && control.tooltip.length > 0
        ToolTip.text: control.tooltip
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: root.close()
    }

    Shortcut {
        sequence: "Space"
        enabled: root.isVideo && root.streamUrl.length > 0
        onActivated: root.togglePlayback()
    }
}
