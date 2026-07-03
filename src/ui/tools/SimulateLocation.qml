import QtQuick
import QtLocation
import QtPositioning
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
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
    property bool recentsExpanded: true
    property bool lastPreparationForced: false
    readonly property int iosMajor: root.device.info.ios_version_major

    ListModel { id: recentLocationsModel }

    MessageDialog {
        id: messageDialog
        title: qsTr("Simulate Location")
        text: ""
    }

    App.DevModeHelper {
        id: devModeHelper
        device: root.device
        iosVersion: root.iosMajor
        onHandled: function(success, forced) {
            if (!success) {
                root.busy = false
                return
            }

            root.applyLocationAfterPreparation(forced)
        }
    }

    function showMessage(message) {
        messageDialog.text = message
        messageDialog.open()
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
            showMessage(qsTr("Please enter valid latitude and longitude values."))
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

            if (success) {
                if (action === "set") {
                    root.saveCurrentLocation()
                    root.showMessage(qsTr("Location applied successfully."))
                } else {
                    root.showMessage(qsTr("Location simulation reset successfully."))
                }
                return
            }

            if (code === 21) {
                if (root.lastPreparationForced) {
                    root.showMessage(qsTr("Developer Mode is still not available. Error code: %1").arg(code))
                    return
                }

                root.busy = true
                devModeHelper.start()
                return
            }

            if (code === 109) {
                root.showMessage(qsTr("Failed to update location simulation: timed out."))
                return
            }

            root.showMessage(qsTr("Failed to update location simulation. Error code: %1").arg(code))
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
                    color: "#4CAF50"
                    border.color: "white"
                    border.width: 2

                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 4
                        color: "white"
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
            }
            
            // Update marker when center changes
            onCenterChanged: {
                marker.coordinate = center
                mapView.updateInputsFromMap(center.latitude, center.longitude)
            }
        }

        Rectangle {
            Layout.preferredWidth: Math.max(300, root.width * 0.32)
            Layout.fillHeight: true
            color: palette.window

            ScrollView {
                anchors.fill: parent
                anchors.margins: 16
                clip: true

                ColumnLayout {
                    width: Math.max(parent.width, 1)
                    spacing: 14

                    SectionBox {
                        title: qsTr("Location")
                        Layout.fillWidth: true

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 8

                            Label {
                                text: qsTr("Latitude")
                                color: App.Theme.textMuted
                            }

                            TextField {
                                id: latitudeField
                                Layout.fillWidth: true
                                text: root.formatCoordinate(root.latitude)
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                selectByMouse: true
                                enabled: !root.busy
                                onEditingFinished: root.validateInputs()
                            }

                            Label {
                                text: qsTr("Longitude")
                                color: App.Theme.textMuted
                            }

                            TextField {
                                id: longitudeField
                                Layout.fillWidth: true
                                text: root.formatCoordinate(root.longitude)
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                selectByMouse: true
                                enabled: !root.busy
                                onEditingFinished: root.validateInputs()
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Button {
                                id: applyButton
                                Layout.fillWidth: true
                                text: root.busy ? qsTr("Applying...") : qsTr("Apply")
                                enabled: !root.busy
                                onClicked: root.applyClicked()
                            }

                            Button {
                                Layout.fillWidth: true
                                text: root.busy ? qsTr("Resetting...") : qsTr("Reset")
                                enabled: !root.busy
                                onClicked: root.resetClicked()
                            }
                        }
                    }

                    SectionBox {
                        title: qsTr("Recent Locations")
                        Layout.fillWidth: true
                        contentSpacing: 0

                        Button {
                            Layout.fillWidth: true
                            flat: true
                            text: root.recentsExpanded ? qsTr("Hide Recent Locations") : qsTr("Show Recent Locations")
                            onClicked: root.recentsExpanded = !root.recentsExpanded
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.recentsExpanded
                            spacing: 8

                            Label {
                                Layout.fillWidth: true
                                visible: recentLocationsModel.count === 0
                                text: qsTr("No recent locations yet.")
                                color: App.Theme.textMuted
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }

                            Repeater {
                                model: recentLocationsModel
                                delegate: Button {
                                    Layout.fillWidth: true
                                    enabled: !root.busy
                                    text: qsTr("%1, %2").arg(model.latitude).arg(model.longitude)
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

                    BusyIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        running: root.busy
                        visible: root.busy
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
