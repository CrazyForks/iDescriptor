import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "../base"
import "../"

AnimatedDialog {
    id: root
    required property string bundleId
    required property string appName

    background: Rectangle {
        radius: 10
        color: palette.window
        border.color: Qt.rgba(0, 0, 0, 0.12)
        border.width: 1
    }
    padding: 20

    modal: true
    focus: true
    width: 440
    title: qsTr("Get IPA")
    standardButtons: Dialog.NoButton
    closePolicy: root.downloading ? Popup.NoAutoClose : Popup.CloseOnPressOutside

    property string taskId: ""
    property bool downloading: false
    property real progress: 0
    property string stateText: ""
    property string outputPath: ""
    property string errorText: ""
    property string completedPath: ""

    function resetState() {
        taskId = ""
        downloading = false
        progress = 0
        stateText = ""
        errorText = ""
        completedPath = ""
        outputPath = settingsManager.ipa_download_path()
    }

    function requestClose() {
        if (downloading) {
            cancelConfirmation.open()
            return
        }
        close()
    }

    function startDownload() {
        errorText = ""
        completedPath = ""
        progress = -1
        stateText = qsTr("Preparing download...")

        const id = apps.download_ipa(bundleId, outputPath)
        if (!id || !id.length) {
            progress = 0
            errorText = qsTr("The App Store service is not initialized.")
            stateText = errorText
            return
        }

        taskId = id
        downloading = true
    }

    onOpened: resetState()
    onClosed: {
        if (taskId.length)
            apps.cancel_task(taskId)
        taskId = ""
        downloading = false
    }

    Keys.onEscapePressed: function(event) {
        root.requestClose()
        event.accepted = true
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.35)
    }

    FolderDialog {
        id: outputDialog
        title: qsTr("Choose download folder")
        onAccepted: root.outputPath = QmlUtils.url_to_path(selectedFolder)
    }

    MessageDialog {
        id: cancelConfirmation
        title: qsTr("Cancel download?")
        text: qsTr("The IPA download is still in progress. Do you want to cancel it and close this dialog?")
        buttons: MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function(button, role) {
            if (button !== MessageDialog.Yes)
                return

            const id = root.taskId
            root.taskId = ""
            root.downloading = false
            if (id.length)
                apps.cancel_task(id)
            root.close()
        }
    }

    Connections {
        target: apps

        function onDownloadIpaProgress(taskId, progress) {
            if (taskId !== root.taskId)
                return
            root.downloading = true
            root.progress = progress
            root.stateText = qsTr("Downloading IPA...")
        }

        function onDownloadIpaFinished(taskId, success, path, error) {
            if (taskId !== root.taskId)
                return

            root.taskId = ""
            root.downloading = false
            root.progress = success ? 1 : 0
            root.completedPath = success ? path : ""
            root.errorText = success ? "" : (error || qsTr("Download failed."))
            root.stateText = success ? qsTr("Saved IPA") : root.errorText
        }
    }

    contentItem: ColumnLayout {
        spacing: 14

        Label {
            Layout.fillWidth: true
            text: root.appName
            font.pixelSize: 18
            font.bold: true
            elide: Text.ElideRight
        }

        Label {
            Layout.fillWidth: true
            text: root.bundleId
            color: "#6e6e73"
            elide: Text.ElideMiddle
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: root.outputPath
                color: "#6e6e73"
                elide: Text.ElideMiddle
            }

            Button {
                text: qsTr("Choose")
                enabled: !root.downloading
                onClicked: outputDialog.open()
            }
        }

        ProgressBar {
            Layout.fillWidth: true
            visible: root.downloading || root.progress > 0
            indeterminate: root.downloading && root.progress < 0
            from: 0
            to: 1
            value: Math.max(0, root.progress)
        }

        Label {
            Layout.fillWidth: true
            text: root.completedPath.length
                  ? qsTr("Saved to %1").arg(root.completedPath)
                  : root.stateText
            color: root.errorText.length ? "#c00" : "#6e6e73"
            wrapMode: Text.WordWrap
            visible: text.length > 0
        }

        RowLayout {
            Layout.fillWidth: true
            Button {
                text: !root.downloading && root.completedPath.length ? qsTr("Open Folder") : ""
                visible: text.length > 0
                enabled: !root.downloading
                onClicked: {
                    if (root.completedPath.length)
                        Qt.openUrlExternally(Helpers.toFileUrl(root.outputPath))
                }
            }
            Item { Layout.fillWidth: true }

            Button {
                text: root.downloading ? qsTr("Cancel") : qsTr("Close")
                onClicked: root.requestClose()
            }

            Button {
                text: qsTr("Get IPA")
                enabled: !root.downloading && root.bundleId.length > 0
                onClicked: root.startDownload()
            }
        }
    }
}
