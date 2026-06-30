import QtQuick 
import QtLocation 
import QtPositioning
import QtQuick.Layouts
import QtQuick.Controls
import "../base"
import "../+windows"


// FIXME: wireup backend logic and add buttons to set the location
ToolWindow {
    id: mapView
    width: 800
    height: 600
    property int latitude: 0.000
    property int longitude: 0.000


    function updateInputsFromMap(latitude, longitude) {
        mapView.latitude = latitude 
        mapView.longitude =  longitude
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
        anchors.fill : parent
        Map {
            id: map
            objectName: "map"
            plugin: osmPlugin
            Layout.fillWidth : true
            Layout.preferredWidth : mapView.width * 0.7
            Layout.fillHeight : true
            center: QtPositioning.coordinate(59.91, 10.75) // Oslo
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
                    var coord = map.toCoordinate(Qt.point(mouse.x, mouse.y))
                    map.center = coord
                    marker.coordinate = coord
                    console.log("Map clicked at:", coord.latitude, coord.longitude)
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
                console.log("Map plugin name:", plugin.name)
                console.log("Map plugin supported:", plugin.isAttached)
                console.log("Available map types:", supportedMapTypes.length)
                
                if (supportedMapTypes.length > 0) {
                    activeMapType = supportedMapTypes[0]
                }
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
            Layout.fillWidth : true
            Layout.preferredWidth : mapView.width * 0.3

            Layout.fillHeight : true
            Label {
                text: mapView.longitude 
            }
        }
    
    }
}