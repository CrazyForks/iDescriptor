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

    property var totalCapacity: 0
    property var systemUsage: 0
    property var appsUsage: 0
    property var mediaUsage: 0
    property var galleryUsage: 0
    property var othersUsage: 0
    property var freeSpace: 0

    property string errorMessage: ""
    property bool ready: false
    property bool loading: true

    function isDarkMode() {
        if (typeof Utils !== "undefined" && Utils.isDarkMode)
            return Utils.isDarkMode()
        return false
    }

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

    function updateState() {
        if (loading) {
            stateView.viewState = StateView.State.Loading
            // stateView.loadingText = qsTr("Loading disk usage...")
            return
        }

        if (errorMessage.length > 0) {
            stateView.viewState = StateView.State.Error
            stateView.errorText = errorMessage
            return
        }

        if (totalCapacity <= 0) {
            stateView.viewState = StateView.State.Error
            // stateView.errorText = qsTr("No disk information available.")
            return
        }

        stateView.viewState = StateView.State.Content
    }

    Timer {
        id: initTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (!root.device || !root.device.service_manager) {
                root.loading = false
                root.errorMessage = qsTr("Failed to retrieve disk usage data.")
                root.updateState()
                return
            }

            // var skipGalleryUsage = root.device.deviceInfo.is_iPhone
            //                        && root.device.deviceInfo.isWireless
            //                        && typeof Utils !== "undefined"
            //                        && Utils.isProductTypeNewer
            //                        && !Utils.isProductTypeNewer(
            //                               root.device.deviceInfo.rawProductType,
            //                               "iPhone10,1")

            root.device.service_manager.fetch_disk_usage()
        }
    }

    Component.onCompleted: {
        loading = true
        errorMessage = ""
        updateState()
        initTimer.start()
    }
 
    Connections {
        target: root.device ? root.device.service_manager : null

        function onDisk_usage_retrieved(success, apps_usage) {
            if (!success) {
                loading = false
                errorMessage = qsTr("Failed to retrieve disk usage data.")
                updateState()
                return
            }

            loading = false
            errorMessage = ""

            totalCapacity = root.device.info["TotalDiskCapacity"] || 0
            systemUsage = root.device.info["TotalSystemCapacity"] || 0
            appsUsage = apps_usage
            mediaUsage = 0
            freeSpace = root.device.info["TotalDataAvailable"] || 0
            // galleryUsage = gallery_usage

            var usedKnown = systemUsage + appsUsage + mediaUsage + galleryUsage
            if (totalCapacity > (freeSpace + usedKnown)) {
                othersUsage = totalCapacity - freeSpace - usedKnown
            } else {
                othersUsage = 0
            }

            updateState()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 0
        anchors.topMargin: 0
        anchors.rightMargin: 14
        anchors.bottomMargin: 10
        spacing: 0

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
            viewState: StateView.State.Loading
            // loadingText: qsTr("Loading disk usage...")
            // errorText: qsTr("Failed to retrieve disk usage data.")

            contentItem: ColumnLayout {
                Layout.fillWidth: true
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
                                // FIXME: cache sizes, do not recompute
                                    .arg(Helpers.formatSize(systemUsage))
                                    .arg(percent(systemUsage))
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
                                    .arg(Helpers.formatSize(appsUsage))
                                    .arg(percent(appsUsage))
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
                                    .arg(Helpers.formatSize(mediaUsage))
                                    .arg(percent(mediaUsage))
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
                                    .arg(Helpers.formatSize(galleryUsage))
                                    .arg(percent(galleryUsage))
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
                                    .arg(Helpers.formatSize(othersUsage))
                                    .arg(percent(othersUsage))
                            }

                            Rectangle {
                                id: freeBar
                                width: segmentWidth(freeSpace, barContainer.width)
                                height: barContainer.height
                                color: isDarkMode()
                                       ? "rgba(255, 255, 255, 0.10)"
                                       : "rgba(0, 0, 0, 0.25)"
                                border.color: "#4f4f4f"
                                border.width: 1
                                radius: 3
                                visible: width > 0

                                HoverHandler { id: freeHover }
                                ToolTip.visible: freeHover.hovered
                                ToolTip.text: qsTr("Free: %1 (%2%)")
                                    .arg(Helpers.formatSize(freeSpace))
                                    .arg(percent(freeSpace))
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        visible: systemUsage > 0
                        text: qsTr("System (%1)").arg(Helpers.formatSize(systemUsage))
                        font.pixelSize: 10
                        color: palette.text
                        leftPadding: 0
                        rightPadding: 4
                    }
                    Item { Layout.fillWidth: true }

                    Text {
                        visible: appsUsage > 0
                        text: qsTr("Apps (%1)").arg(Helpers.formatSize(appsUsage))
                        font.pixelSize: 10
                        color: palette.text
                        leftPadding: 0
                        rightPadding: 4
                    }
                    Item { Layout.fillWidth: true }

                    Text {
                        visible: mediaUsage > 0
                        text: qsTr("Media (%1)").arg(Helpers.formatSize(mediaUsage))
                        font.pixelSize: 10
                        color: palette.text
                        leftPadding: 0
                        rightPadding: 4
                    }
                    Item { Layout.fillWidth: true }

                    Text {
                        visible: galleryUsage > 0
                        text: qsTr("Gallery (%1)").arg(Helpers.formatSize(galleryUsage))
                        font.pixelSize: 10
                        color: palette.text
                        leftPadding: 0
                        rightPadding: 4
                    }
                    Item { Layout.fillWidth: true }

                    Text {
                        visible: othersUsage > 0
                        text: qsTr("Others (%1)").arg(Helpers.formatSize(othersUsage))
                        font.pixelSize: 10
                        color: palette.text
                        leftPadding: 0
                        rightPadding: 4
                    }
                    Item { Layout.fillWidth: true }

                    Text {
                        visible: freeSpace > 0
                        text: qsTr("Free (%1)").arg(Helpers.formatSize(freeSpace))
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