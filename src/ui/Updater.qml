pragma Singleton

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import "." as App
import "./base"

DefaultWindow {
    id: root
    width: 620
    height: 560
    minimumWidth: 460
    minimumHeight: 420
    title: qsTr("Updater - iDescriptor")
    visible: false
    autoVisible: false
    modality: Qt.ApplicationModal
    color: App.Theme.windowBackground
    setupMacOSWindowStyle: Qt.platform.os === "osx"


    enum ViewState {
        Checking,
        UpdateAvailable,
        Downloading,
        Downloaded,
        Error
    }

    readonly property var backend: UpdaterImp
    property var profile: ({})
    property int viewState: Updater.UpdateAvailable
    property string errorText: ""
    property string downloadedPath: ""
    property real progress: 0
    property bool manualCheck: false
    readonly property bool packageManagerManaged: !!root.profile.package_manager_managed
    readonly property bool canDownload: !root.packageManagerManaged && !!root.profile.browser_download_url
    readonly property bool shouldOpenDownloadedFile: !!root.profile.update_procedure_open_file
    readonly property bool shouldRevealDownloadedFile: !!root.profile.update_procedure_open_file_dir
    readonly property bool hasExternalUpdateAction:
        root.profile.delivery_kind === "flatpak"
        || root.profile.delivery_kind === "windowsStore"

    function componentForState(state) {
        switch (state) {
        case Updater.Checking:
            return checkingPageComponent
        case Updater.Downloading:
            return downloadingPageComponent
        case Updater.Downloaded:
            return downloadedPageComponent
        case Updater.Error:
            return errorPageComponent
        default:
            return updateAvailablePageComponent
        }
    }

    function showView(state) {
        root.viewState = state
        var component = root.componentForState(state)

        if (!nav.currentItem) {
            nav.push(component)
            return
        }

        if (nav.currentItem.pageState === state)
            return

        nav.replace(component)
    }

    function showWindow() {
        root.visible = true
        root.raise()
        root.requestActivate()
    }

    function checkForUpdates(manual) {
        root.manualCheck = manual
        root.errorText = ""
        if (manual)
            root.openChecking()

        if (backend && typeof backend.check_for_updates === "function")
            backend.check_for_updates(manual)
    }

    function checkAutomatically() {
        if (!settingsManager.auto_check_updates()) {
            console.log("auto_check_updates is false skipping...")
            return
        }

        console.log("Looking for updates...")

        checkForUpdates(false)
    }

    function openChecking() {
        root.showView(Updater.Checking)
        root.showWindow()
    }

    function openUpdate(profileData) {
        root.profile = profileData || {}
        root.errorText = ""
        root.progress = 0
        root.showView(Updater.UpdateAvailable)
        root.showWindow()
    }

    function showError(message) {
        root.errorText = message || qsTr("The update check failed.")
        root.showView(Updater.Error)
        root.showWindow()
    }

    function showNoUpdate() {
        root.errorText = ""
        root.hide()
        noUpdateDialog.open()
    }

    function startDownload() {
        root.showView(Updater.Downloading)
        if (root.backend && typeof root.backend.download_update === "function")
            root.backend.download_update()
    }

    function closeOrOpenDownloadedUpdate() {
        if (root.shouldOpenDownloadedFile && root.backend
                && typeof root.backend.open_downloaded_update === "function") {
            root.backend.open_downloaded_update()
        } else {
            root.hide()
        }
    }

    function revealDownloadedUpdate() {
        if (root.backend && typeof root.backend.reveal_downloaded_update === "function")
            root.backend.reveal_downloaded_update()
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
                || qsTr("Please use your package manager to update iDescriptor.")
    }

    function updatePromptText() {
        switch (root.profile.delivery_kind) {
        case "flatpak":
            return qsTr("A newer version is available. Update iDescriptor through Flatpak or your software center.")
        case "windowsStore":
            return qsTr("A newer version is available. Update iDescriptor through Microsoft Store.")
        case "packageManager":
            return root.packageManagerText()
        case "releasePage":
            return qsTr("A newer version is available, but this build has no configured direct-update package.")
        }

        if (!root.canDownload)
            return qsTr("A newer version is available, but no matching download was found for this system.")
        return qsTr("Download and install when you are ready. Your current settings and connected devices will not be changed.")
    }

    function externalActionText() {
        switch (root.profile.delivery_kind) {
        case "flatpak":
            return qsTr("Open Flatpak Page")
        case "windowsStore":
            return qsTr("Open Microsoft Store")
        default:
            return ""
        }
    }

    function openExternalUpdatePage() {
        var updateUrl = root.profile.external_update_url || ""
        var fallbackUrl = root.profile.external_update_fallback_url || ""

        if (updateUrl.length > 0 && Qt.openUrlExternally(updateUrl))
            return

        if (fallbackUrl.length > 0)
            Qt.openUrlExternally(fallbackUrl)
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
            root.progress = progressValue
            root.showView(Updater.Downloading)
        }

        function onDownload_finished(path) {
            root.downloadedPath = path
            root.progress = 1
            root.showView(Updater.Downloaded)
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

    component PrimaryButton: Button {
        id: control
        font.bold: true
        padding: 14
        contentItem: Text {
            text: control.text
            color: App.Theme.textSelected
            font: control.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: 10
            color: !control.enabled ? Qt.rgba(App.Theme.accent.r, App.Theme.accent.g, App.Theme.accent.b, 0.45)
                  : control.down ? App.Theme.accentPressed
                  : control.hovered ? App.Theme.accentHover
                  : App.Theme.accent
        }
    }

    component SecondaryButton: Button {
        id: control
        padding: 14
        contentItem: Text {
            text: control.text
            color: App.Theme.text
            font: control.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: 10
            color: control.down ? App.Theme.pressed : control.hovered ? App.Theme.hover : App.Theme.controlFill
            border.color: App.Theme.controlStroke
            border.width: 1
        }
    }

    component StatusBadge: Rectangle {
        property string symbol: ""
        property color symbolColor: App.Theme.accent
        Layout.preferredWidth: 58
        Layout.preferredHeight: 58
        radius: 18
        color: Qt.rgba(symbolColor.r, symbolColor.g, symbolColor.b, App.Theme.darkMode ? 0.18 : 0.12)

        Text {
            anchors.centerIn: parent
            text: parent.symbol
            color: parent.symbolColor
            font.pixelSize: 30
            font.weight: Font.DemiBold
        }
    }

    component Card: Rectangle {
        radius: 14
        color: App.Theme.groupedBackground
        border.color: App.Theme.softBgBorder
        border.width: 1
    }

    Rectangle {
        anchors.fill: parent
        color: App.Theme.windowBackground
    }

    StackView {
        id: nav
        anchors.fill: parent
        initialItem: updateAvailablePageComponent
        clip: true

        pushEnter: Transition {
            PropertyAnimation { property: "x"; from: root.width; to: 0; duration: 320; easing.type: Easing.OutCubic }
            PropertyAnimation { property: "opacity"; from: 0.55; to: 1; duration: 320; easing.type: Easing.OutCubic }
        }
        pushExit: Transition {
            PropertyAnimation { property: "x"; from: 0; to: -root.width; duration: 320; easing.type: Easing.OutCubic }
            PropertyAnimation { property: "opacity"; from: 1; to: 0.55; duration: 320; easing.type: Easing.OutCubic }
        }
        popEnter: Transition {
            PropertyAnimation { property: "x"; from: -root.width; to: 0; duration: 280; easing.type: Easing.OutCubic }
            PropertyAnimation { property: "opacity"; from: 0.55; to: 1; duration: 280; easing.type: Easing.OutCubic }
        }
        popExit: Transition {
            PropertyAnimation { property: "x"; from: 0; to: nav.width; duration: 280; easing.type: Easing.OutCubic }
            PropertyAnimation { property: "opacity"; from: 1; to: 0.55; duration: 280; easing.type: Easing.OutCubic }
        }
        replaceEnter: Transition {
            PropertyAnimation { property: "x"; from: root.width * 0.16; to: 0; duration: 260; easing.type: Easing.OutCubic }
            PropertyAnimation { property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
        }
        replaceExit: Transition {
            PropertyAnimation { property: "x"; from: 0; to: -root.width * 0.10; duration: 200; easing.type: Easing.OutCubic }
            PropertyAnimation { property: "opacity"; from: 1; to: 0; duration: 180; easing.type: Easing.OutCubic }
        }
    }

    Component {
        id: updateAvailablePageComponent

        Item {
            readonly property int pageState: Updater.UpdateAvailable

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 30
                spacing: 18

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    StatusBadge {
                        symbol: "↑"
                        symbolColor: App.Theme.accent
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("A new version is available")
                            color: App.Theme.text
                            font.pixelSize: 22
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Version %1").arg(root.profile.tag_name || root.profile.version || "")
                            color: App.Theme.textMuted
                            font.pixelSize: 13
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: root.updatePromptText()
                    color: App.Theme.textMuted
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                }

                Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    visible: !root.packageManagerManaged && !!root.profile.file_name

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Label {
                            Layout.fillWidth: true
                            text: root.profile.file_name || ""
                            color: App.Theme.text
                            elide: Text.ElideMiddle
                        }

                        Label {
                            text: root.formatBytes(root.profile.asset_size || -1)
                            color: App.Theme.textMuted
                            font.pixelSize: 12
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 150

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 8

                        Label {
                            text: qsTr("What’s new")
                            color: App.Theme.text
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            TextArea {
                                width: parent.width
                                text: root.profile.body || root.profile.changelog
                                      || qsTr("No change log was provided for this release.")
                                textFormat: Text.MarkdownText
                                readOnly: true
                                selectByMouse: true
                                wrapMode: Text.WordWrap
                                color: App.Theme.text
                                background: Rectangle { color: "transparent" }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    SecondaryButton {
                        Layout.fillWidth: true
                        text: root.packageManagerManaged || !root.canDownload ? qsTr("Close") : qsTr("Not now")
                        onClicked: root.hide()
                    }

                    PrimaryButton {
                        Layout.fillWidth: true
                        visible: root.canDownload
                        text: qsTr("Download Update")
                        onClicked: root.startDownload()
                    }

                    PrimaryButton {
                        Layout.fillWidth: true
                        visible: root.hasExternalUpdateAction
                        text: root.externalActionText()
                        onClicked: root.openExternalUpdatePage()
                    }
                }
            }
        }
    }

    Component {
        id: checkingPageComponent

        Item {
            readonly property int pageState: Updater.Checking

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 60, 360)
                spacing: 16

                BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    running: true
                    implicitWidth: 42
                    implicitHeight: 42
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Checking for updates")
                    color: App.Theme.text
                    font.pixelSize: 21
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Looking for a newer release of iDescriptor…")
                    color: App.Theme.textMuted
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Component {
        id: downloadingPageComponent

        Item {
            readonly property int pageState: Updater.Downloading

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 60, 400)
                spacing: 16

                StatusBadge {
                    Layout.alignment: Qt.AlignHCenter
                    symbol: "↓"
                    symbolColor: App.Theme.accent
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Downloading update")
                    color: App.Theme.text
                    font.pixelSize: 21
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Please keep iDescriptor open while the update downloads.")
                    color: App.Theme.textMuted
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                ProgressBar {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    indeterminate: root.progress <= 0
                    from: 0
                    to: 1
                    value: root.progress
                    background: Rectangle {
                        implicitHeight: 8
                        radius: height / 2
                        color: App.Theme.softBg
                    }
                    contentItem: Item {
                        implicitHeight: 8
                        Rectangle {
                            width: parent.width * (root.progress <= 0 ? 0.18 : root.progress)
                            height: parent.height
                            radius: height / 2
                            color: App.Theme.accent
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("%1% downloaded").arg(Math.round(root.progress * 100))
                    color: App.Theme.textMuted
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Component {
        id: downloadedPageComponent

        Item {
            readonly property int pageState: Updater.Downloaded

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 30
                spacing: 18

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    StatusBadge {
                        symbol: "✓"
                        symbolColor: App.Theme.systemGreen
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Update downloaded")
                            color: App.Theme.text
                            font.pixelSize: 22
                            font.weight: Font.DemiBold
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Version %1 is ready.").arg(root.profile.tag_name || root.profile.version || "")
                            color: App.Theme.textMuted
                            font.pixelSize: 13
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: root.procedureText()
                    color: App.Theme.text
                    font.pixelSize: 15
                    wrapMode: Text.WordWrap
                }

                Label {
                    Layout.fillWidth: true
                    visible: root.procedureInformativeText().length > 0
                    text: root.procedureInformativeText()
                    color: App.Theme.textMuted
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                }

                Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(58, downloadedPathLabel.implicitHeight + 28)

                    Label {
                        id: downloadedPathLabel
                        anchors.fill: parent
                        anchors.margins: 14
                        text: qsTr("Downloaded to %1").arg(root.downloadedPath)
                        color: App.Theme.textMuted
                        font.pixelSize: 12
                        wrapMode: Text.WrapAnywhere
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    SecondaryButton {
                        Layout.fillWidth: true
                        visible: root.shouldRevealDownloadedFile
                        text: qsTr("Reveal Download")
                        onClicked: root.revealDownloadedUpdate()
                    }

                    SecondaryButton {
                        Layout.fillWidth: true
                        visible: !root.shouldRevealDownloadedFile
                        text: qsTr("Close")
                        onClicked: root.hide()
                    }

                    PrimaryButton {
                        Layout.fillWidth: true
                        text: root.shouldOpenDownloadedFile ? qsTr("Open Update") : qsTr("Close")
                        onClicked: root.closeOrOpenDownloadedUpdate()
                    }
                }
            }
        }
    }

    Component {
        id: errorPageComponent

        Item {
            readonly property int pageState: Updater.Error

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 60, 400)
                spacing: 16

                StatusBadge {
                    Layout.alignment: Qt.AlignHCenter
                    symbol: "!"
                    symbolColor: App.Theme.systemRed
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Update check failed")
                    color: App.Theme.text
                    font.pixelSize: 21
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                }

                Label {
                    Layout.fillWidth: true
                    text: root.errorText
                    color: App.Theme.textMuted
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                PrimaryButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                    text: qsTr("Close")
                    onClicked: root.hide()
                }
            }
        }
    }
}
