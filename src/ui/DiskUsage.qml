import QtQuick
import QtQuick.Controls 
import QtQuick.Layouts 
import QtQuick.Controls.impl 
import Qt5Compat.GraphicalEffects
import "./base"

Item {
    id: root
    implicitHeight: 80

    required property var device
    required property real galleryUsage
    required property bool galleryUsageResolved

    readonly property real totalCapacity: Number(device.info["TotalDiskCapacity"] || 0)
    readonly property real systemUsage: Number(device.info["TotalSystemCapacity"] || 0)
    property real appsUsage: 0
    readonly property real mediaUsage: 0
    readonly property real freeSpace: Number(device.info["FreeBytes"] !== undefined
                                                  && device.info["FreeBytes"] !== null
                                              ? device.info["FreeBytes"]
                                              : device.info["TotalDataAvailable"] || 0)
    readonly property real othersUsage: Math.max(0, totalCapacity - freeSpace
                                                 - systemUsage - appsUsage
                                                 - mediaUsage - galleryUsage)

    property string errorMessage: ""
    property bool appsUsageResolved: false

    readonly property string systemSizeText: Helpers.formatSize(systemUsage)
    readonly property string appsSizeText: Helpers.formatSize(appsUsage)
    readonly property string mediaSizeText: Helpers.formatSize(mediaUsage)
    readonly property string gallerySizeText: Helpers.formatSize(galleryUsage)
    readonly property string othersSizeText: Helpers.formatSize(othersUsage)
    readonly property string freeSizeText: Helpers.formatSize(freeSpace)

    readonly property string systemPercentText: percent(systemUsage)
    readonly property string appsPercentText: percent(appsUsage)
    readonly property string mediaPercentText: percent(mediaUsage)
    readonly property string galleryPercentText: percent(galleryUsage)
    readonly property string othersPercentText: percent(othersUsage)
    readonly property string freePercentText: percent(freeSpace)

    function percent(value) {
        if (totalCapacity <= 0)
            return "0.0"
        return ((value / totalCapacity) * 100).toFixed(1)
    }

    function segmentWidth(value, totalWidth) {
        if (totalCapacity <= 0 || value <= 0)
            return 0
        var w = Math.floor(value / totalCapacity * totalWidth)
        return w <= 0 ? 1 : w
    }

    function fetchAppsDiskUsage() {
        appsUsageResolved = false
        errorMessage = ""
        root.device.service_manager.fetch_apps_disk_usage()
    }

    Component.onCompleted: {
        Qt.callLater(root.fetchAppsDiskUsage)
    }
 
    Connections {
        target: root.device.service_manager

        function onAppsDiskUsageRetrieved(success, apps_usage) {
            if (!success) {
                errorMessage = qsTr("Failed to retrieve disk usage data.")
                appsUsageResolved = true
                return
            }

            appsUsage = Number(apps_usage)
            errorMessage = ""
            appsUsageResolved = true
        }
    }

    ColumnLayout {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.85
        anchors.topMargin: 0
        anchors.bottomMargin: 10
        spacing: 4

        Text {
            Layout.fillWidth: true
            text: qsTr("Disk Usage")
            horizontalAlignment: Text.AlignHCenter
            font.bold: true
            color: palette.text
        }

        StateView {
            id: stateView
            Layout.fillWidth: true
            Layout.fillHeight: true
            autoSwitchContent: false
            viewState: !root.appsUsageResolved || !root.galleryUsageResolved
                       ? StateView.State.Loading
                       : root.errorMessage.length > 0 || root.totalCapacity <= 0
                         ? StateView.State.Error
                         : StateView.State.Content
            errorText: root.errorMessage.length > 0
                       ? root.errorMessage
                       : qsTr("No disk information available.")
            retryable: true
            onRetryRequested: root.fetchAppsDiskUsage()

            contentItem: Item {
                anchors.fill: parent

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Item {
                        id: barContainer
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20

                        Rectangle {
                            id: clipContainer
                            anchors.fill: parent
                            color: "transparent"
                            border.width: 0
                            radius: 5
                            clip: true
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: clipContainer.width
                                    height: clipContainer.height
                                    radius: clipContainer.radius
                                    visible: false
                                }
                            }
                            Row {
                                id: barRow
                                anchors.fill: parent
                                spacing: 0

                            Rectangle {
                                id: systemBar
                                width: segmentWidth(systemUsage, barContainer.width)
                                height: barContainer.height
                                color: "#a1384d"
                                border.color: "#e64a5b"
                                border.width: 1
                                visible: width > 0

                                HoverHandler { id: systemHover }
                                ToolTip.visible: systemHover.hovered
                                ToolTip.text: qsTr("System: %1 (%2%)")
                                    .arg(root.systemSizeText)
                                    .arg(root.systemPercentText)
                            }

                            Rectangle {
                                id: appsBar
                                width: segmentWidth(appsUsage, barContainer.width)
                                height: barContainer.height
                                color: "#4f869f"
                                border.color: "#63b4da"
                                border.width: 1
                                visible: width > 0

                                HoverHandler { id: appsHover }
                                ToolTip.visible: appsHover.hovered
                                ToolTip.text: qsTr("Apps: %1 (%2%)")
                                    .arg(root.appsSizeText)
                                    .arg(root.appsPercentText)
                            }

                            Rectangle {
                                id: mediaBar
                                width: segmentWidth(mediaUsage, barContainer.width)
                                height: barContainer.height
                                color: "#2ECC71"
                                border.width: 0
                                visible: width > 0

                                HoverHandler { id: mediaHover }
                                ToolTip.visible: mediaHover.hovered
                                ToolTip.text: qsTr("Media: %1 (%2%)")
                                    .arg(root.mediaSizeText)
                                    .arg(root.mediaPercentText)
                            }

                            Rectangle {
                                id: galleryBar
                                width: segmentWidth(galleryUsage, barContainer.width)
                                height: barContainer.height
                                color: "#9b59b6"
                                border.color: "#b36cd1"
                                border.width: 1
                                visible: width > 0

                                HoverHandler { id: galleryHover }
                                ToolTip.visible: galleryHover.hovered
                                ToolTip.text: qsTr("Gallery: %1 (%2%)")
                                    .arg(root.gallerySizeText)
                                    .arg(root.galleryPercentText)
                            }

                            Rectangle {
                                id: othersBar
                                width: segmentWidth(othersUsage, barContainer.width)
                                height: barContainer.height
                                color: "#a28729"
                                border.color: "#c4a32d"
                                border.width: 1
                                visible: width > 0

                                HoverHandler { id: othersHover }
                                ToolTip.visible: othersHover.hovered
                                ToolTip.text: qsTr("Others: %1 (%2%)")
                                    .arg(root.othersSizeText)
                                    .arg(root.othersPercentText)
                            }

                            Rectangle {
                                id: freeBar
                                width: segmentWidth(freeSpace, barContainer.width)
                                height: barContainer.height
                                color: Theme.softBg.darker(0.1)
                                border.color: Theme.softBgBorder
                                // border.color: "#4f4f4f"
                                border.width: 1
                                visible: width > 0

                                HoverHandler { id: freeHover }
                                ToolTip.visible: freeHover.hovered
                                ToolTip.text: qsTr("Free: %1 (%2%)")
                                    .arg(root.freeSizeText)
                                    .arg(root.freePercentText)
                            }
                        }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                    Text {
                        visible: systemUsage > 0
                        text: qsTr("System (%1)").arg(root.systemSizeText)
                        font.pixelSize: 10
                        color: palette.text
                        leftPadding: 0
                        rightPadding: 4
                    }
                    Item { Layout.fillWidth: true }

                    Text {
                        visible: appsUsage > 0
                        text: qsTr("Apps (%1)").arg(root.appsSizeText)
                        font.pixelSize: 10
                        color: palette.text
                        leftPadding: 0
                        rightPadding: 4
                    }
                    Item { Layout.fillWidth: true }

                    Text {
                        visible: mediaUsage > 0
                        text: qsTr("Media (%1)").arg(root.mediaSizeText)
                        font.pixelSize: 10
                        color: palette.text
                        leftPadding: 0
                        rightPadding: 4
                    }
                    Item { Layout.fillWidth: true }

                    Text {
                        visible: galleryUsage > 0
                        text: qsTr("Gallery (%1)").arg(root.gallerySizeText)
                        font.pixelSize: 10
                        color: palette.text
                        leftPadding: 0
                        rightPadding: 4
                    }
                    Item { Layout.fillWidth: true }

                    Text {
                        visible: othersUsage > 0
                        text: qsTr("Others (%1)").arg(root.othersSizeText)
                        font.pixelSize: 10
                        color: palette.text
                        leftPadding: 0
                        rightPadding: 4
                    }
                    Item { Layout.fillWidth: true }

                        Text {
                            visible: freeSpace > 0
                            text: qsTr("Free (%1)").arg(root.freeSizeText)
                            font.pixelSize: 10
                            color: palette.text
                            leftPadding: 0
                            rightPadding: 4
                        }
                    }
                }
            }
        }
    }
}
