pragma Singleton

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window

Window {
    id: root
    width: 620
    height: 560
    minimumWidth: 460
    minimumHeight: 420
    title: qsTr("Updater - iDescriptor")
    visible: false
    modality: Qt.ApplicationModal

    readonly property var backend: typeof UpdaterImp !== "undefined" ? UpdaterImp : null
    property var profile: ({})
    property bool checking: false
    property bool downloading: false
    property bool downloaded: false
    property string errorText: ""
    property string downloadedPath: ""
    property real progress: 0
    property bool manualCheck: false
    readonly property bool packageManagerManaged: !!root.profile.package_manager_managed
    readonly property bool canDownload: !root.packageManagerManaged && !!root.profile.browser_download_url
    readonly property bool shouldOpenDownloadedFile: !!root.profile.update_procedure_open_file
    readonly property bool shouldRevealDownloadedFile: !!root.profile.update_procedure_open_file_dir

    function checkForUpdates(manual) {
        root.manualCheck = manual
        root.errorText = ""
        if (manual)
            root.openChecking()

        if (backend && typeof backend.check_for_updates === "function")
            backend.check_for_updates(manual)
    }

    function checkAutomatically() {
        if (typeof settingsManager !== "undefined"
                && settingsManager
                && typeof settingsManager.auto_check_updates === "function"
                && !settingsManager.auto_check_updates()) {
            return
        }

        checkForUpdates(false)
    }

    function openChecking() {
        root.checking = true
        root.downloading = false
        root.downloaded = false
        root.visible = true
        root.raise()
        root.requestActivate()
    }

    function openUpdate(profileData) {
        root.profile = profileData || {}
        root.checking = false
        root.downloading = false
        root.downloaded = false
        root.errorText = ""
        root.progress = 0
        root.visible = true
        root.raise()
        root.requestActivate()
    }

    function showError(message) {
        root.checking = false
        root.downloading = false
        root.downloaded = false
        root.errorText = message || qsTr("The update check failed.")
        root.visible = true
        root.raise()
        root.requestActivate()
    }

    function showNoUpdate() {
        root.checking = false
        root.downloading = false
        root.downloaded = false
        root.errorText = ""
        root.hide()
        noUpdateDialog.open()
    }

    function formatBytes(bytes) {
        if (bytes < 0)
            return qsTr("Unknown size")
        if (bytes < 1024)
            return qsTr("%1 B").arg(bytes)

        var units = ["KB", "MB", "GB"]
        var value = bytes / 1024
        var unitIndex = 0
        while (value >= 1024 && unitIndex < units.length - 1) {
            value /= 1024
            unitIndex += 1
        }
        return qsTr("%1 %2").arg(value.toFixed(value >= 10 ? 1 : 2)).arg(units[unitIndex])
    }

    function procedureText() {
        return root.profile.update_procedure_text || qsTr("Update downloaded.")
    }

    function procedureInformativeText() {
        return root.profile.update_procedure_informative_text || ""
    }

    function packageManagerText() {
        return root.profile.package_manager_managed_message
                || qsTr("This installation is managed by a package manager. Please use it to update iDescriptor.")
    }

    function updatePromptText() {
        if (root.packageManagerManaged)
            return root.packageManagerText()
        if (!root.canDownload)
            return qsTr("A newer version is available, but no matching download was found for this system.")
        return qsTr("Would you like to download the update now?")
    }

    Connections {
        target: root.backend
        enabled: !!root.backend

        function onUpdate_available(profileData) {
            root.openUpdate(profileData)
        }

        function onNo_update_found() {
            if (root.manualCheck)
                root.showNoUpdate()
        }

        function onCheck_failed(message) {
            root.showError(message)
        }

        function onDownload_progress(downloadedBytes, totalBytes, progressValue) {
            root.checking = false
            root.downloading = true
            root.downloaded = false
            root.progress = progressValue
        }

        function onDownload_finished(path) {
            root.checking = false
            root.downloading = false
            root.downloaded = true
            root.downloadedPath = path
            root.progress = 1
        }

        function onDownload_failed(message) {
            root.showError(message)
        }
    }

    MessageDialog {
        id: noUpdateDialog
        title: qsTr("Updates")
        text: qsTr("You are using the latest version of iDescriptor.")
    }

    Rectangle {
        anchors.fill: parent
        color: palette.window
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        Label {
            Layout.fillWidth: true
            text: {
                if (root.errorText.length > 0)
                    return qsTr("Update Check Failed")
                if (root.downloaded)
                    return qsTr("Update Downloaded")
                if (root.downloading)
                    return qsTr("Downloading Update")
                if (root.checking)
                    return qsTr("Checking for Updates")
                return qsTr("Version %1 of %2 has been released!")
                        .arg(root.profile.tag_name || root.profile.version || "")
                        .arg(root.profile.application_name || "iDescriptor")
            }
            wrapMode: Text.WordWrap
            font.pixelSize: 18
            font.bold: true
            color: palette.text
        }

        Label {
            Layout.fillWidth: true
            visible: !root.checking && !root.downloading && !root.downloaded && root.errorText.length === 0
            text: root.updatePromptText()
            wrapMode: Text.WordWrap
            color: palette.text
        }

        Label {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            text: root.errorText
            wrapMode: Text.WordWrap
            color: palette.text
        }

        Label {
            Layout.fillWidth: true
            visible: root.downloaded
            text: root.procedureText() + "\n\n" + root.procedureInformativeText() + "\n\n" + qsTr("Downloaded to %1.").arg(root.downloadedPath)
            wrapMode: Text.WrapAnywhere
            color: palette.text
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.checking || root.downloading
            spacing: 8

            ProgressBar {
                Layout.fillWidth: true
                indeterminate: root.checking || root.progress <= 0
                from: 0
                to: 1
                value: root.progress
            }

            Label {
                Layout.fillWidth: true
                text: root.checking ? qsTr("Looking for a newer release...") : qsTr("%1% downloaded").arg(Math.round(root.progress * 100))
                horizontalAlignment: Text.AlignHCenter
                color: palette.text
            }
        }

        GroupBox {
            Layout.fillWidth: true
            visible: !root.checking && !root.downloading && !root.downloaded && root.errorText.length === 0
            title: qsTr("Change log")

            ScrollView {
                width: parent.width
                height: Math.max(180, root.height - 260)
                clip: true

                TextArea {
                    width: parent.width
                    text: root.profile.body || root.profile.changelog || qsTr("No change log was provided for this release.")
                    textFormat: Text.MarkdownText
                    readOnly: true
                    selectByMouse: true
                    wrapMode: Text.WordWrap
                    color: palette.text
                    background: Rectangle {
                        color: "transparent"
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                Layout.fillWidth: true
                visible: !root.checking && !root.downloading && !root.downloaded && root.errorText.length === 0
                text: root.packageManagerManaged
                        ? ""
                        : root.profile.file_name
                        ? qsTr("%1, %2").arg(root.profile.file_name).arg(root.formatBytes(root.profile.asset_size || -1))
                        : ""
                elide: Text.ElideMiddle
                color: palette.text
            }

            Item {
                Layout.fillWidth: true
                visible: root.checking || root.downloading || root.downloaded || root.errorText.length > 0
            }

            Button {
                text: {
                    if (root.downloaded && root.shouldRevealDownloadedFile)
                        return qsTr("Reveal")
                    return qsTr("No")
                }
                enabled: !root.checking && !root.downloading
                visible: root.errorText.length === 0 && !root.packageManagerManaged && root.canDownload && (!root.downloaded || root.shouldRevealDownloadedFile)
                onClicked: {
                    if (root.downloaded && root.shouldRevealDownloadedFile) {
                        if (root.backend && typeof root.backend.reveal_downloaded_update === "function")
                            root.backend.reveal_downloaded_update()
                    } else {
                        root.hide()
                    }
                }
            }

            Button {
                text: {
                    if (root.errorText.length > 0)
                        return qsTr("Close")
                    if (root.downloaded)
                        return root.shouldOpenDownloadedFile ? qsTr("Open") : qsTr("Close")
                    if (root.downloading)
                        return qsTr("Downloading")
                    if (!root.canDownload)
                        return qsTr("Close")
                    return qsTr("Yes")
                }
                enabled: !root.checking && !root.downloading
                onClicked: {
                    if (root.errorText.length > 0) {
                        root.hide()
                    } else if (root.downloaded) {
                        if (root.shouldOpenDownloadedFile && root.backend && typeof root.backend.open_downloaded_update === "function")
                            root.backend.open_downloaded_update()
                        else
                            root.hide()
                    } else if (!root.canDownload) {
                        root.hide()
                    } else if (root.backend && typeof root.backend.download_update === "function") {
                        root.downloading = true
                        root.backend.download_update()
                    }
                }
            }
        }
    }
}
