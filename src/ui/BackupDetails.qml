import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./base"
import "." as App

Item {
    id: root

    required property string udid
    required property string backupRoot
    property string title: ""
    property var backupInfo: null
    property var deviceSummary: ({})
    property string hoveredDomain: ""
    property int totalFiles: 0
    property double totalBytes: 0

    signal backRequested()

    ListModel { id: domainModel }

    function fetchBackupInfo() {
        stateView.viewState = StateView.State.Loading
        stateView.errorText = ""
        root.backupInfo = null
        root.deviceSummary = {}
        root.hoveredDomain = ""
        root.totalFiles = 0
        root.totalBytes = 0
        domainModel.clear()
        backupManager.get_backup_info(root.udid, root.backupRoot)
    }

    function diskUsageColor(index) {
        var colors = [
            "#9b59b6",
            "#4f869f",
            "#a28729",
            "#a1384d",
            "#2ECC71"
        ]
        return colors[index % colors.length]
    }

    function diskUsageBorderColor(index) {
        var colors = [
            "#b36cd1",
            "#63b4da",
            "#c4a32d",
            "#e64a5b",
            "#2ECC71"
        ]
        return colors[index % colors.length]
    }

    function segmentWidth(size, totalWidth) {
        if (root.totalBytes <= 0 || size <= 0 || totalWidth <= 0)
            return 0

        var w = Math.floor(size / root.totalBytes * totalWidth)
        return Math.max(3, w)
    }

    function percent(size) {
        if (root.totalBytes <= 0 || size <= 0)
            return "0.0"
        return ((size / root.totalBytes) * 100).toFixed(1)
    }

    function readValue(text, key) {
        var re = new RegExp("(?:^|[,{}])\\s*" + key
                            + "\\s*[:=]\\s*(?:\\\"([^\\\"]*)\\\"|([^,}\\n>]+))")
        var match = re.exec(text || "")
        if (!match)
            return ""
        return String(match[1] !== undefined ? match[1] : match[2]).trim()
    }

    function backupDateText() {
        var raw = root.deviceSummary.backupDate || ""
        if (!raw)
            return qsTr("Unknown")

        // MobileBackup2 returns dates such as "2026-07-19 20:56:15 +0000".
        // Convert the timezone to ISO 8601 so QML parses it consistently.
        var normalized = raw.replace(
            /^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+([+-]\d{2})(\d{2})$/,
            "$1T$2$3:$4")
        var date = new Date(normalized)
        if (isNaN(date.getTime()))
            return raw

        return Qt.formatDateTime(date, "yyyy-MM-dd hh:mm")
    }

    function parseBackupContent(content) {
        domainModel.clear()

        var statusMatch = /<MBStatus:\s*([^>]*)>/.exec(content || "")
        var driveMatch = /<MBDriveProperties:\s*([^>]*)>/.exec(content || "")
        var statusText = statusMatch ? statusMatch[1] : ""
        var driveText = driveMatch ? driveMatch[1] : ""

        root.deviceSummary = {
            backupState: readValue(statusText, "backupState") || qsTr("Unknown"),
            snapshotState: readValue(statusText, "snapshotState"),
            fullBackup: readValue(statusText, "fullBackup"),
            backupDate: readValue(statusText, "date"),
            encrypted: readValue(driveText, "encrypted") === "1",
            passcodeSet: readValue(driveText, "passcodeSet") === "1",
            productVersion: readValue(driveText, "ProductVersion"),
            productType: readValue(driveText, "ProductType"),
            buildVersion: readValue(driveText, "BuildVersion"),
            serialNumber: readValue(driveText, "SerialNumber"),
            deviceName: readValue(driveText, "DeviceName") || root.title || root.udid
        }

        var rows = []
        var totalCount = 0
        var totalSize = 0
        var lines = String(content || "").split("\n")
        for (var i = 0; i < lines.length; ++i) {
            var match = /^\s*(\d+)\s+(\d+)\s+(.+?)\s*$/.exec(lines[i])
            if (!match)
                continue

            var count = Number(match[1])
            var size = Number(match[2])
            var name = match[3]
            if (name === "Total") {
                totalCount = count
                totalSize = size
                continue
            }

            rows.push({
                name: name,
                count: count,
                size: size
            })
        }

        rows.sort(function(a, b) { return b.size - a.size })
        root.totalFiles = totalCount
        root.totalBytes = totalSize

        for (var j = 0; j < rows.length; ++j) {
            domainModel.append({
                name: rows[j].name,
                count: rows[j].count,
                size: rows[j].size,
                color: diskUsageColor(j),
                borderColor: diskUsageBorderColor(j)
            })
        }
    }

    function backupModeText() {
        if (!deviceSummary)
            return qsTr("Unknown")
        if (deviceSummary.backupState === "new")
            return qsTr("New")
        if (deviceSummary.fullBackup === "1")
            return qsTr("Full")
        return qsTr("Incremental")
    }

    Component.onCompleted: fetchBackupInfo()

    Connections {
        target: backupManager

        function onBackupInfoReady(udid, success, res) {
            console.log("Backup info ready for udid:", udid, "success:", success, "res:", JSON.stringify(res))
            if (udid !== root.udid)
                return

            if (!success) {
                stateView.errorText = res || qsTr("Failed to load backup details.")
                stateView.viewState = StateView.State.Error
                return
            }

            try {
                root.backupInfo = JSON.parse(res)
                root.parseBackupContent(root.backupInfo.Content || "")
                stateView.viewState = StateView.State.Content
            } catch (e) {
                stateView.errorText = qsTr("Failed to parse backup details.")
                stateView.viewState = StateView.State.Error
            }
        }
    }

    StateView {
        id: stateView
        anchors.fill: parent
        autoSwitchContent: false
        retryable: true
        onRetryRequested: root.fetchBackupInfo()

        contentItem: ScrollView {
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: Math.max(0, Math.min(860, stateView.width - 48))
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.margins: 24
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 18
                    spacing: 10

                    Button {
                        text: qsTr("Back")
                        onClicked: root.backRequested()
                    }

                    Item { Layout.fillWidth: true }
                }

                SectionBox {
                    Layout.fillWidth: true
                    title: root.deviceSummary.deviceName || root.title || qsTr("Backup Summary")
                    contentSpacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: root.backupModeText()
                            color: App.Theme.textMuted
                            leftPadding: 10
                            rightPadding: 10
                            topPadding: 4
                            bottomPadding: 4
                            background: Rectangle {
                                radius: 9
                                color: App.Theme.softBg
                                border.color: App.Theme.controlStroke
                                border.width: 1
                            }
                        }

                        Label {
                            text: root.deviceSummary.encrypted ? qsTr("Encrypted") : qsTr("Not Encrypted")
                            color: root.deviceSummary.encrypted ? App.Theme.textMuted : App.Theme.dangerText
                            leftPadding: 10
                            rightPadding: 10
                            topPadding: 4
                            bottomPadding: 4
                            background: Rectangle {
                                radius: 9
                                color: App.Theme.softBg
                                border.color: root.deviceSummary.encrypted ? App.Theme.controlStroke : App.Theme.dangerText
                                border.width: 1
                            }
                        }

                        Label {
                            text: root.deviceSummary.passcodeSet ? qsTr("Passcode Was Set") : qsTr("No Passcode")
                            color: root.deviceSummary.passcodeSet ? App.Theme.textMuted : App.Theme.dangerText
                            leftPadding: 10
                            rightPadding: 10
                            topPadding: 4
                            bottomPadding: 4
                            background: Rectangle {
                                radius: 9
                                color: App.Theme.softBg
                                border.color: root.deviceSummary.passcodeSet ? App.Theme.controlStroke : App.Theme.dangerText
                                border.width: 1
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Label {
                            Layout.fillWidth: true
                            text: QmlUtils.get_device_name(root.deviceSummary.productType)
                            color: App.Theme.text
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("iOS %1 - Serial %2")
                                .arg(root.deviceSummary.productVersion || qsTr("Unknown"))
                                .arg(root.deviceSummary.serialNumber || qsTr("Unknown"))
                            color: App.Theme.textMuted
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Backup Date: %1").arg(root.backupDateText())
                            color: App.Theme.textMuted
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        id: barContainer
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20

                        Rectangle {
                            id: clipContainer
                            anchors.fill: parent
                            radius: 5
                            color: "transparent"
                            clip: true

                            Row {
                                anchors.fill: parent
                                spacing: 0

                                Repeater {
                                    model: domainModel

                                    Rectangle {
                                        width: root.segmentWidth(model.size, barContainer.width)
                                        height: barContainer.height
                                        color: model.color
                                        border.color: model.borderColor
                                        border.width: root.hoveredDomain === model.name ? 2 : 1
                                        opacity: root.hoveredDomain.length === 0 || root.hoveredDomain === model.name ? 1 : 0.42
                                        visible: width > 0

                                        HoverHandler {
                                            onHoveredChanged: root.hoveredDomain = hovered ? model.name : ""
                                        }

                                        ToolTip.visible: root.hoveredDomain === model.name
                                        ToolTip.text: qsTr("%1: %2 (%3%)")
                                            .arg(model.name)
                                            .arg(App.Helpers.formatSize(model.size))
                                            .arg(root.percent(model.size))
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Repeater {
                            model: domainModel

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 34
                                color: root.hoveredDomain === model.name ? App.Theme.hover : "transparent"
                                radius: 5

                                HoverHandler {
                                    onHoveredChanged: root.hoveredDomain = hovered ? model.name : ""
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    spacing: 10

                                    Rectangle {
                                        Layout.preferredWidth: 9
                                        Layout.preferredHeight: 9
                                        radius: 2
                                        color: model.color
                                        border.color: model.borderColor
                                        border.width: 1
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: model.name
                                        color: App.Theme.text
                                        elide: Text.ElideRight
                                    }

                                    Label {
                                        Layout.preferredWidth: 72
                                        text: qsTr("%n file(s)", "", model.count)
                                        color: App.Theme.textMuted
                                        horizontalAlignment: Text.AlignRight
                                        font.family: "monospace"
                                    }

                                    Label {
                                        Layout.preferredWidth: 92
                                        text: App.Helpers.formatSize(model.size)
                                        color: App.Theme.textMuted
                                        horizontalAlignment: Text.AlignRight
                                        font.family: "monospace"
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: App.Theme.sidebarDivider
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Item { Layout.fillWidth: true }

                        Label {
                            text: qsTr("%n file(s)", "", root.totalFiles)
                            color: App.Theme.text
                            horizontalAlignment: Text.AlignRight
                            font.family: "monospace"
                        }

                        Label {
                            Layout.preferredWidth: 110
                            text: App.Helpers.formatSize(root.totalBytes)
                            color: App.Theme.text
                            horizontalAlignment: Text.AlignRight
                            font.family: "monospace"
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }
}
