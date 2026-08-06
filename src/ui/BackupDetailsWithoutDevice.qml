// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

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
    property int totalApplications: 0
    property double totalBytes: 0
    property bool encrypted: false

    signal backRequested()

    ListModel { id: domainModel }

    function fetchBackupInfo() {
        stateView.viewState = StateView.State.Loading
        stateView.errorText = ""
        root.backupInfo = null
        root.deviceSummary = {}
        root.hoveredDomain = ""
        root.totalFiles = 0
        root.totalApplications = 0
        root.totalBytes = 0
        domainModel.clear()
        console.log("Fetching backup info for UDID:", root.udid, "Backup Root:", root.backupRoot)
        backupManager.get_backup_info_without_device(root.udid, root.backupRoot)
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

    function segmentWidth(count, totalWidth) {
        if (root.totalApplications <= 0 || count <= 0 || totalWidth <= 0)
            return 0

        var w = Math.floor(count / root.totalApplications * totalWidth)
        return Math.max(3, w)
    }

    function percent(count) {
        if (root.totalApplications <= 0 || count <= 0)
            return "0.0"
        return ((count / root.totalApplications) * 100).toFixed(1)
    }

    function unknownText(value) {
        if (value === undefined || value === null || String(value).length === 0)
            return qsTr("Unknown")
        return String(value)
    }

    function backupDateText() {
        var raw = root.deviceSummary.backupDate || ""
        if (!raw)
            return qsTr("Unknown")

        var normalized = raw.replace(/\.(\d{3})\d*Z$/, ".$1Z")
        var date = new Date(normalized)
        if (isNaN(date.getTime()))
            return raw

        return Qt.formatDateTime(date, "yyyy-MM-dd hh:mm")
    }

    function containerClassText(value) {
        if (value === "Data/Application")
            return qsTr("Applications")
        if (value === "Data/PluginKitPlugin")
            return qsTr("App Extensions")
        if (value === "Shared/AppGroup")
            return qsTr("Shared App Groups")
        if (!value)
            return qsTr("Other")
        return String(value)
    }

    function parseBackupManifest(manifest) {
        manifest = manifest || {}
        domainModel.clear()

        var lockdown = manifest.Lockdown || {}
        var applications = manifest.Applications || {}
        var appKeys = Object.keys(applications)
        var groups = {}

        for (var i = 0; i < appKeys.length; ++i) {
            var app = applications[appKeys[i]] || {}
            var className = app.ContainerContentClass || qsTr("Other")
            groups[className] = (groups[className] || 0) + 1
        }

        var rows = Object.keys(groups).map(function(name) {
            return {
                name: containerClassText(name),
                sourceName: name,
                count: groups[name]
            }
        })

        rows.sort(function(a, b) { return b.count - a.count })

        root.totalApplications = appKeys.length
        root.totalFiles = Number(manifest.FolderFiles || 0)
        root.totalBytes = Number(manifest.FolderSize || 0)
        root.deviceSummary = {
            backupDate: manifest.Date || "",
            encrypted: manifest.IsEncrypted === true,
            passcodeSet: manifest.WasPasscodeSet === true,
            productVersion: lockdown.ProductVersion || "",
            productType: lockdown.ProductType || "",
            buildVersion: lockdown.BuildVersion || "",
            serialNumber: lockdown.SerialNumber || "",
            deviceName: lockdown.DeviceName || root.title || root.udid,
            systemDomainsVersion: manifest.SystemDomainsVersion || "",
            manifestVersion: manifest.Version || "",
            uniqueDeviceId: lockdown.UniqueDeviceID || root.udid
        }

        for (var j = 0; j < rows.length; ++j) {
            domainModel.append({
                name: rows[j].name,
                sourceName: rows[j].sourceName,
                count: rows[j].count,
                color: diskUsageColor(j),
                borderColor: diskUsageBorderColor(j)
            })
        }
    }

    Component.onCompleted: fetchBackupInfo()

    Connections {
        target: backupManager

        function onBackupInfoReadyWithoutDevice(udid, success, res) {
            if (udid !== root.udid)
                return

            if (!success) {
                stateView.errorText = res || qsTr("Failed to load backup details.")
                stateView.viewState = StateView.State.Error
                return
            }

            try {
                root.backupInfo = JSON.parse(res)
                root.parseBackupManifest(root.backupInfo)
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

                Label {
                    Layout.fillWidth: true
                    text: !root.encrypted ?qsTr("Tip: Connect the device that created this backup to view more details.") : qsTr("For now encrypted backup details are limited. Having the device connected will not provide more information.")
                    horizontalAlignment: Text.AlignLeft
                }

                SectionBox {
                    Layout.fillWidth: true
                    title: root.deviceSummary.deviceName || root.title || qsTr("Backup Summary")
                    contentSpacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: qsTr("Offline Device Backup")
                            visible: !root.encrypted
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
                            text: root.deviceSummary.passcodeSet ? qsTr("Screen Passcode Set") : qsTr("No Screen Passcode")
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

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 18

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                Layout.fillWidth: true
                                text: qsTr("Total Size")
                                color: App.Theme.textMuted
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.fillWidth: true
                                text: App.Helpers.formatSize(root.totalBytes)
                                color: App.Theme.text
                                font.pixelSize: 24
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 1
                            Layout.fillHeight: true
                            color: App.Theme.sidebarDivider
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                Layout.fillWidth: true
                                text: qsTr("Files")
                                color: App.Theme.textMuted
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.fillWidth: true
                                text: qsTr("%n file(s)", "", root.totalFiles)
                                color: App.Theme.text
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 1
                            Layout.fillHeight: true
                            color: App.Theme.sidebarDivider
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                Layout.fillWidth: true
                                text: qsTr("Apps and Containers")
                                color: App.Theme.textMuted
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.fillWidth: true
                                text: qsTr("%n item(s)", "", root.totalApplications)
                                color: App.Theme.text
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 18
                        rowSpacing: 8

                        Label {
                            text: qsTr("Device Model")
                            color: App.Theme.textMuted
                            font.pixelSize: 12
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.deviceSummary.productType ? QmlUtils.get_device_name(root.deviceSummary.productType) : qsTr("Unknown")
                            color: App.Theme.text
                            elide: Text.ElideRight
                        }

                        Label {
                            text: qsTr("iOS Version")
                            color: App.Theme.textMuted
                            font.pixelSize: 12
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("%1 (%2)")
                                .arg(root.unknownText(root.deviceSummary.productVersion))
                                .arg(root.unknownText(root.deviceSummary.buildVersion))
                            color: App.Theme.text
                            elide: Text.ElideRight
                        }

                        Label {
                            text: qsTr("Serial")
                            color: App.Theme.textMuted
                            font.pixelSize: 12
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.unknownText(root.deviceSummary.serialNumber)
                            color: App.Theme.text
                            elide: Text.ElideRight
                        }

                        Label {
                            text: qsTr("Backup Date")
                            color: App.Theme.textMuted
                            font.pixelSize: 12
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.backupDateText()
                            color: App.Theme.text
                            elide: Text.ElideRight
                        }

                        Label {
                            text: qsTr("Manifest")
                            color: App.Theme.textMuted
                            font.pixelSize: 12
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Version %1, domains %2")
                                .arg(root.unknownText(root.deviceSummary.manifestVersion))
                                .arg(root.unknownText(root.deviceSummary.systemDomainsVersion))
                            color: App.Theme.text
                            elide: Text.ElideRight
                        }

                        Label {
                            text: qsTr("UDID")
                            color: App.Theme.textMuted
                            font.pixelSize: 12
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.deviceSummary.uniqueDeviceId || root.udid
                            color: App.Theme.text
                            elide: Text.ElideMiddle
                        }
                    }
                }

                SectionBox {
                    Layout.fillWidth: true
                    title: qsTr("Application Containers")
                    contentSpacing: 12

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
                                        width: root.segmentWidth(model.count, barContainer.width)
                                        height: barContainer.height
                                        color: model.color
                                        border.color: model.borderColor
                                        border.width: root.hoveredDomain === model.sourceName ? 2 : 1
                                        opacity: root.hoveredDomain.length === 0 || root.hoveredDomain === model.sourceName ? 1 : 0.42
                                        visible: width > 0

                                        HoverHandler {
                                            onHoveredChanged: root.hoveredDomain = hovered ? model.sourceName : ""
                                        }

                                        ToolTip.visible: root.hoveredDomain === model.sourceName
                                        ToolTip.text: qsTr("%1: %n item(s)", "", model.count)
                                            .arg(model.name)
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
                                color: root.hoveredDomain === model.sourceName ? App.Theme.hover : "transparent"
                                radius: 5

                                HoverHandler {
                                    onHoveredChanged: root.hoveredDomain = hovered ? model.sourceName : ""
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
                                        Layout.preferredWidth: 92
                                        text: qsTr("%n item(s)", "", model.count)
                                        color: App.Theme.textMuted
                                        horizontalAlignment: Text.AlignRight
                                        font.family: "monospace"
                                    }

                                    Label {
                                        Layout.preferredWidth: 68
                                        text: qsTr("%1%").arg(root.percent(model.count))
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

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Backup folder")
                            color: App.Theme.text
                            elide: Text.ElideRight
                        }

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
