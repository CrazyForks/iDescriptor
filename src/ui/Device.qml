import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./installed-apps"


Item {
    id: root

    property var info: ({})
    property string udid: ""
    required property int currentSection
    required property var device

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

        Loader {
            active: root.currentSection === 2 || item
            sourceComponent: galleryComponent
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
        id: galleryComponent

        DeviceGallery {
            udid: root.udid
            info: root.info
        }
    }

    Component {
        id: filesComponent

        FilesSection {
            udid: root.udid
        }
    }
}