import QtQuick
import QtLocation
import QtPositioning
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Controls.impl
import "../base"
import ".." as App

ToolWindow {
    id: root
    width: 920
    height: 640
    title: qsTr("Simulate Location - iDescriptor")

    property double latitude: 59.91
    property double longitude: 10.75
    property bool busy: false
    property string busyAction: ""
    property bool recentsExpanded: true
    property bool lastPreparationForced: false
    readonly property int iosMajor: root.device.info.ios_version_major

    ListModel { id: recentLocationsModel }

    App.DevModeHelper {
        id: devModeHelper
        device: root.device
        onHandled: function(success, forced) {
            if (!success) {
                root.busy = false
                root.busyAction = ""
                App.Helpers.showError(root, qsTr("Developer Mode preparation did not complete. Location simulation was not changed."))
                return
            }

            root.applyLocationAfterPreparation(forced)
        }
    }

    function formatCoordinate(value) {
        return Number(value).toFixed(6)
    }

    function updateInputsFromMap(latitude, longitude) {
        root.latitude = latitude
        root.longitude = longitude
        latitudeField.text = formatCoordinate(latitude)
        longitudeField.text = formatCoordinate(longitude)
    }

    function setMapLocation(latitude, longitude) {
        const coord = QtPositioning.coordinate(latitude, longitude)
        map.center = coord
        marker.coordinate = coord
        updateInputsFromMap(latitude, longitude)
    }

    function parseCoordinate(text) {
        const value = Number(String(text).trim())
        return isFinite(value) ? value : NaN
    }

    function validateInputs() {
        const lat = parseCoordinate(latitudeField.text)
        const lon = parseCoordinate(longitudeField.text)

        if (!isFinite(lat) || !isFinite(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
            App.Helpers.showWarning(root, qsTr("Please enter a latitude between −90 and 90 and a longitude between −180 and 180."))
            return false
        }

        root.latitude = lat
        root.longitude = lon
        setMapLocation(lat, lon)
        return true
    }

    function applyClicked() {
        if (root.busy)
            return

        if (!validateInputs())
            return

        root.busy = true
        root.busyAction = "set"
        devModeHelper.start()
    }

    function applyLocationAfterPreparation(forced) {
        root.lastPreparationForced = forced
        root.device.service_manager.set_location(latitudeField.text.trim(), longitudeField.text.trim())
    }

    function resetClicked() {
        if (root.busy)
            return

        root.busy = true
        root.busyAction = "reset"
        root.device.service_manager.clear_location()
    }

    function loadRecentLocations() {
        recentLocationsModel.clear()

        const recentLocations = settingsManager.get_recent_locations()
        for (let i = 0; i < recentLocations.length; i++) {
            const item = recentLocations[i]
            recentLocationsModel.append({
                latitude: String(item.latitude || ""),
                longitude: String(item.longitude || "")
            })
        }
    }

    function saveCurrentLocation() {
        settingsManager.save_recent_location(latitudeField.text.trim(), longitudeField.text.trim(), "")
        loadRecentLocations()
    }

    Connections {
        target: root.device.service_manager

        function onLocationSimulationCompleted(success, code, action) {
            root.busy = false
            root.busyAction = ""

            if (success) {
                if (action === "set") {
                    root.saveCurrentLocation()
                    App.Helpers.showInfo(root, qsTr("The simulated location was applied successfully."))
                } else {
                    App.Helpers.showInfo(root, qsTr("Location simulation was reset successfully."))
                }
                return
            }

            if (code === 21) {
                if (root.lastPreparationForced) {
                    App.Helpers.showError(root, qsTr("Developer Mode is still not available. Error code: %1").arg(code))
                    return
                }

                root.busy = true
                root.busyAction = "set"
                devModeHelper.start()
                return
            }

            if (code === 109) {
                App.Helpers.showError(root, qsTr("The location request timed out. Please verify the device connection and try again."))
                return
            }

            App.Helpers.showError(root, qsTr("Failed to update location simulation. Error code: %1").arg(code))
        }
    }

    Connections {
        target: settingsManager
        function onRecentLocationsChanged() {
            root.loadRecentLocations()
        }
    }

    Component.onCompleted: {
        setMapLocation(root.latitude, root.longitude)
        loadRecentLocations()
    }

    Plugin {
        id: osmPlugin
        name: "osm"

        PluginParameter {
            name: "osm.mapping.providersrepository.disabled"
            value: "true"
        }
        PluginParameter {
            name: "osm.mapping.providersrepository.address"
            value: "http://maps-redirect.qt.io/osm/5.6/"
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Map {
            id: map
            objectName: "map"
            plugin: osmPlugin
            Layout.fillWidth: true
            Layout.preferredWidth: root.width * 0.68
            Layout.fillHeight: true
            center: QtPositioning.coordinate(root.latitude, root.longitude)
            zoomLevel: 14
            property geoCoordinate startCentroid

            // Marker for current location
            MapQuickItem {
                id: marker
                coordinate: map.center
                anchorPoint.x: 12
                anchorPoint.y: 12

                sourceItem: Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: App.Theme.systemBlue
                    border.color: App.Theme.controlFill
                    border.width: 3

                    Rectangle {
                        anchors.centerIn: parent
                        width: 6
                        height: 6
                        radius: 3
                        color: App.Theme.controlFill
                    }
                }
            }

            // Handle click to update location
            MouseArea {
                anchors.fill: parent
                onClicked: function(mouse) {
                    const coord = map.toCoordinate(Qt.point(mouse.x, mouse.y))
                    root.setMapLocation(coord.latitude, coord.longitude)
                }
            }

            PinchHandler {
                id: pinch
                target: null
                onActiveChanged: if (active) {
                    map.startCentroid = map.toCoordinate(pinch.centroid.position, false)
                }
                onScaleChanged: (delta) => {
                    map.zoomLevel += Math.log2(delta)
                    map.alignCoordinateToPoint(map.startCentroid, pinch.centroid.position)
                }
                onRotationChanged: (delta) => {
                    map.bearing -= delta
                    map.alignCoordinateToPoint(map.startCentroid, pinch.centroid.position)
                }
                grabPermissions: PointerHandler.TakeOverForbidden
            }

            WheelHandler {
                id: wheel
                // workaround for QTBUG-87646 / QTBUG-112394 / QTBUG-112432:
                // Magic Mouse pretends to be a trackpad but doesn't work with PinchHandler
                // and we don't yet distinguish mice and trackpads on Wayland either
                acceptedDevices: Qt.platform.pluginName === "cocoa" || Qt.platform.pluginName === "wayland"
                                ? PointerDevice.Mouse | PointerDevice.TouchPad
                                : PointerDevice.Mouse
                rotationScale: 1/120
                property: "zoomLevel"
            }

            DragHandler {
                id: drag
                target: null
                onTranslationChanged: (delta) => map.pan(-delta.x, -delta.y)
            }

            Shortcut {
                enabled: map.zoomLevel < map.maximumZoomLevel
                sequence: StandardKey.ZoomIn
                onActivated: map.zoomLevel = Math.round(map.zoomLevel + 1)
            }

            Shortcut {
                enabled: map.zoomLevel > map.minimumZoomLevel
                sequence: StandardKey.ZoomOut
                onActivated: map.zoomLevel = Math.round(map.zoomLevel - 1)
            }

            Component.onCompleted: {
                if (supportedMapTypes.length > 0)
                    activeMapType = supportedMapTypes[0]
            }

            onErrorChanged: {
                console.log("Map error:", error)
                console.log("Error string:", errorString)
                if (errorString.length > 0)
                    App.Helpers.showWarning(root, qsTr("The map could not be loaded: %1").arg(errorString))
            }
            
            // Update marker when center changes
            onCenterChanged: {
                marker.coordinate = center
                root.updateInputsFromMap(center.latitude, center.longitude)
            }
        }

        Item {
            Layout.preferredWidth: Math.max(320, root.width * 0.34)
            Layout.fillHeight: true
            // color: App.Theme.windowBackground

            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                width: 1
                color: App.Theme.sidebarDivider
            }

            ScrollView {
                id: sidebarScrollView
                anchors.fill: parent
                anchors.leftMargin: 21
                anchors.rightMargin: 20
                anchors.topMargin: 20
                anchors.bottomMargin: 20
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    width: Math.max(sidebarScrollView.availableWidth, 1)
                    spacing: 16

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Simulated Location")
                        color: App.Theme.text
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.topMargin: -10
                        text: qsTr("Choose a point on the map or enter precise coordinates.")
                        color: App.Theme.textMuted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    SectionBox {
                        title: qsTr("Coordinates")
                        Layout.fillWidth: true
                        padding: 14
                        titleSpacing: 10

                        background: Rectangle {
                            color: App.Theme.elevatedSurface
                            border.color: App.Theme.separator
                            border.width: 1
                            radius: 14
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 10

                            Label {
                                text: qsTr("Latitude")
                                color: App.Theme.textMuted
                                font.pixelSize: 12
                            }

                            TextField {
                                id: latitudeField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                text: root.formatCoordinate(root.latitude)
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                selectByMouse: true
                                enabled: !root.busy
                                color: enabled ? App.Theme.text : App.Theme.textMuted
                                selectionColor: App.Theme.selection
                                selectedTextColor: App.Theme.textSelected
                                leftPadding: 12
                                rightPadding: 12
                                font.pixelSize: 14
                                background: Rectangle {
                                    radius: 10
                                    color: latitudeField.enabled ? App.Theme.controlFill : App.Theme.softBg
                                    border.color: latitudeField.activeFocus ? App.Theme.accent : App.Theme.controlStroke
                                    border.width: latitudeField.activeFocus ? 2 : 1
                                }
                                onEditingFinished: root.validateInputs()
                            }

                            Label {
                                text: qsTr("Longitude")
                                color: App.Theme.textMuted
                                font.pixelSize: 12
                            }

                            TextField {
                                id: longitudeField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                text: root.formatCoordinate(root.longitude)
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                selectByMouse: true
                                enabled: !root.busy
                                color: enabled ? App.Theme.text : App.Theme.textMuted
                                selectionColor: App.Theme.selection
                                selectedTextColor: App.Theme.textSelected
                                leftPadding: 12
                                rightPadding: 12
                                font.pixelSize: 14
                                background: Rectangle {
                                    radius: 10
                                    color: longitudeField.enabled ? App.Theme.controlFill : App.Theme.softBg
                                    border.color: longitudeField.activeFocus ? App.Theme.accent : App.Theme.controlStroke
                                    border.width: longitudeField.activeFocus ? 2 : 1
                                }
                                onEditingFinished: root.validateInputs()
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 8

                            Button {
                                id: applyButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                text: root.busy && root.busyAction === "set" ? qsTr("Applying…") : qsTr("Apply")
                                enabled: !root.busy
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                contentItem: Label {
                                    text: applyButton.text
                                    color: applyButton.enabled ? App.Theme.textSelected : App.Theme.textMuted
                                    font: applyButton.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: 10
                                    color: !applyButton.enabled ? App.Theme.softBg
                                        : applyButton.down ? App.Theme.accentPressed
                                        : applyButton.hovered ? App.Theme.accentHover
                                        : App.Theme.accent
                                }
                                onClicked: root.applyClicked()
                            }

                            Button {
                                id: resetButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                text: root.busy && root.busyAction === "reset" ? qsTr("Resetting…") : qsTr("Reset")
                                enabled: !root.busy
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                ToolTip.visible: hovered
                                ToolTip.delay: 500
                                ToolTip.text: qsTr("Clear the simulated location and return the device to its original location.")
                                contentItem: Label {
                                    text: resetButton.text
                                    color: resetButton.enabled ? App.Theme.dangerText : App.Theme.textMuted
                                    font: resetButton.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: 10
                                    color: !resetButton.enabled ? App.Theme.softBg
                                        : resetButton.down ? App.Theme.pressed
                                        : resetButton.hovered ? App.Theme.hover
                                        : App.Theme.controlFill
                                    border.color: App.Theme.controlStroke
                                    border.width: 1
                                }
                                onClicked: root.resetClicked()
                            }
                        }
                    }

                    SectionBox {
                        Layout.fillWidth: true
                        contentSpacing: 0
                        padding: 0

                        background: Rectangle {
                            color: App.Theme.elevatedSurface
                            border.color: App.Theme.separator
                            border.width: 1
                            radius: 14
                        }

                        Button {
                            id: recentsButton
                            Layout.fillWidth: true
                            Layout.preferredHeight: 50
                            flat: true
                            leftPadding: 14
                            rightPadding: 14
                            text: qsTr("Recent Locations")

                            contentItem: RowLayout {
                                spacing: 8

                                Label {
                                    Layout.fillWidth: true
                                    text: recentsButton.text
                                    color: App.Theme.text
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }

                                Rectangle {
                                    implicitWidth: countLabel.implicitWidth + 12
                                    implicitHeight: 22
                                    radius: 11
                                    color: App.Theme.selectionSoft

                                    Label {
                                        id: countLabel
                                        anchors.centerIn: parent
                                        text: recentLocationsModel.count
                                        color: App.Theme.systemBlue
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Label {
                                    text: qsTr("›")
                                    color: App.Theme.icon
                                    font.pixelSize: 24
                                    rotation: root.recentsExpanded ? 90 : 0

                                    Behavior on rotation {
                                        NumberAnimation {
                                            duration: App.Theme.fastAnimation
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }
                            }

                            background: Rectangle {
                                radius: 14
                                color: recentsButton.down ? App.Theme.pressed
                                    : recentsButton.hovered ? App.Theme.hover
                                    : "transparent"
                            }
                            onClicked: root.recentsExpanded = !root.recentsExpanded
                        }

                        Item {
                            id: recentsContainer
                            Layout.fillWidth: true
                            Layout.preferredHeight: recentLocationsContent.implicitHeight * expansion
                            clip: true
                            opacity: expansion
                            visible: expansion > 0
                            property real expansion: root.recentsExpanded ? 1 : 0

                            Behavior on expansion {
                                NumberAnimation {
                                    duration: App.Theme.mediumAnimation
                                    easing.type: Easing.OutCubic
                                }
                            }

                            ColumnLayout {
                                id: recentLocationsContent
                                width: parent.width
                                spacing: 0

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: App.Theme.separator
                                }

                                Label {
                                    Layout.fillWidth: true
                                    Layout.margins: 16
                                    visible: recentLocationsModel.count === 0
                                    text: qsTr("Locations you use will appear here.")
                                    color: App.Theme.textMuted
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }

                                Repeater {
                                    model: recentLocationsModel
                                    delegate: Button {
                                        id: recentLocationButton
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 46
                                        enabled: !root.busy
                                        leftPadding: 14
                                        rightPadding: 14
                                        text: qsTr("%1, %2").arg(model.latitude).arg(model.longitude)

                                        contentItem: RowLayout {
                                            spacing: 10

                                            IconImage {
                                                source: "qrc:/resources/icons/material-symbols_location-on-outline.svg"
                                                sourceSize.width: 18
                                                sourceSize.height: 18
                                                color: recentLocationButton.enabled ? App.Theme.systemBlue : App.Theme.textMuted
                                            }

                                            Label {
                                                Layout.fillWidth: true
                                                text: recentLocationButton.text
                                                color: recentLocationButton.enabled ? App.Theme.text : App.Theme.textMuted
                                                font.pixelSize: 13
                                                elide: Text.ElideRight
                                            }

                                            Label {
                                                text: qsTr("›")
                                                color: App.Theme.textMuted
                                                font.pixelSize: 20
                                            }
                                        }

                                        background: Rectangle {
                                            color: recentLocationButton.down ? App.Theme.pressed
                                                : recentLocationButton.hovered ? App.Theme.hover
                                                : "transparent"

                                            Rectangle {
                                                anchors.top: parent.top
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.leftMargin: 42
                                                height: index > 0 ? 1 : 0
                                                color: App.Theme.separator
                                            }
                                        }

                                        onClicked: {
                                            const lat = root.parseCoordinate(model.latitude)
                                            const lon = root.parseCoordinate(model.longitude)
                                            if (isFinite(lat) && isFinite(lon))
                                                root.setMapLocation(lat, lon)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    BusyIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        running: root.busy
                        visible: root.busy
                        palette.highlight: App.Theme.accent
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
