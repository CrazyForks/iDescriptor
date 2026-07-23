import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "installed-apps"
import "." as App


Item {
    id: root

    property var info: ({})
    property string udid: ""
    required property int currentSection
    required property var device
    property real galleryUsage: 0
    property bool galleryUsageResolved: false

    function enableWifiForNewWiredDevice() {
        if (!root.device || !root.info || root.info.is_wireless)
            return
        if (!settingsManager.auto_enable_wifi_connections())
            return
        if (settingsManager.has_seen_device(root.udid))
            return

        App.DeviceContext.enableWifiConnections(root.device, root)
    }

    Component.onCompleted: Qt.callLater(root.enableWifiForNewWiredDevice)

    StackLayout {
        anchors.fill: parent
        currentIndex: root.currentSection

        Loader {
            active: root.currentSection === 0 || item
            sourceComponent: deviceInfoComponent
        }

        Loader {
            active: root.currentSection === 1 || item
            sourceComponent: installedAppsComponent
        }

        /*load gallery as soon as possible*/
        DeviceGallery {
            device: root.device
            onGallerySizeQueried: function(size) {
                console.log("Gallery size queried: " + size)
                root.galleryUsage = Math.max(0, Number(size))
                root.galleryUsageResolved = true
            }
        }

        Loader {
            active: root.currentSection === 3 || item
            sourceComponent: filesComponent
        }
    }

    /* lazy load all comps */
    Component {
        id: deviceInfoComponent

        DeviceInfo {
            info: root.info
            device: root.device
            galleryUsage: root.galleryUsage
            galleryUsageResolved: root.galleryUsageResolved
        }
    }

    Component {
        id: installedAppsComponent

        InstalledApps {
            udid: root.udid
            device: root.device
        }
    }

    Component {
        id: filesComponent

        FilesSection {
            device: root.device
        }
    }
}
