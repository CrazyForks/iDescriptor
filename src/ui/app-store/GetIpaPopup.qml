import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "../" as App

Dialog {
    id: root
    required property string bundleId
    required property string appName

    modal: true
    width: 440
    title: qsTr("Get IPA")
    standardButtons: Dialog.NoButton
    closePolicy: downloading ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)

    property bool downloading: false
    property real progress: 0
    property string stateText: ""
    property string outputPath: ""
    property string errorText: ""
    property string completedPath: ""

    FolderDialog {
        id: outputDialog
        title: qsTr("Choose download folder")
        onAccepted: root.outputPath = selectedFolder.toString().replace("file:///", "/").replace("file://", "")
    }

    Connections {
        target: apps

        function onDownload_ipa_progress(bundleId, progress, state) {
            if (bundleId !== root.bundleId) return
            root.downloading = true
            root.progress = progress
            root.stateText = state
        }

        function onDownload_ipa_finished(bundleId, success, path, error) {
            if (bundleId !== root.bundleId) return
            root.downloading = false
            root.progress = success ? 1 : root.progress
            root.completedPath = path || ""
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
                text: root.outputPath.length ? root.outputPath : qsTr("Default download folder")
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
            from: 0
            to: 1
            value: root.progress
        }

        Label {
            Layout.fillWidth: true
            text: root.completedPath.length ? qsTr("Saved to %1").arg(root.completedPath) : root.stateText
            color: root.errorText.length ? "#c00" : "#6e6e73"
            wrapMode: Text.WordWrap
            visible: text.length > 0
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }

            Button {
                text: root.downloading ? qsTr("Downloading...") : qsTr("Cancel")
                enabled: !root.downloading
                onClicked: root.close()
            }

            Button {
                text: qsTr("Get IPA")
                enabled: !root.downloading && root.bundleId.length > 0
                onClicked: {
                    root.errorText = ""
                    root.completedPath = ""
                    root.progress = 0
                    root.stateText = qsTr("Preparing download...")
                    root.downloading = true
                    apps.download_ipa(root.bundleId, root.outputPath)
                }
            }
        }
    }
}
