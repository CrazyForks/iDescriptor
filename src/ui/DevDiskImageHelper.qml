import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./base"
import "." as App

Dialog {
    id: root

    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 32 : 460, 460)
    height: 220
    title: qsTr("Developer Disk Image - iDescriptor")

    required property var device
    // property string udid: ""
    required property int iosVersion
    property string version: ""
    property string statusText: qsTr("Please wait...")

    signal mountingCompleted(bool success)

    function showError(message) {
        stateView.errorText = message
        stateView.viewState = StateView.State.Error
    }

    function start() {
        open()
        retry()
    }

    function retry() {
        stateView.viewState = StateView.State.Loading
        statusText = qsTr("Please wait...")
        startTimer.restart()
    }

    function checkAndMount() {
        if (!root.device || !root.device.service_manager) {
            showError(qsTr("No device service manager is available."))
            return
        }

        // FIXME: we dont have developer disk images for ios 6 and below
        if (root.iosVersion <= 5) {
            showError(qsTr("Developer disk image is not available for this iOS version. Please use a device with iOS 6 or above."))
            return
        }

        stateView.viewState = StateView.State.Content

        App.Helpers.connectOnce(root.device.service_manager.mounted_image_retrieved, function(success, isLocked, signature, sigLength) {
            if (!success) {
                if (isLocked) {
                    showError(qsTr("The device appears to be locked. Please unlock the device and try again."))
                    return
                }

                showError(qsTr("Failed to retrieve mounted developer disk image info."))
                return
            }

            if (sigLength > 0) {
                finishWithSuccess(false)
                return
            }

            prepareCompatibleImage()
        })

        root.device.service_manager.get_mounted_image()
    }

    function prepareCompatibleImage() {
        const info = DevImgsManager.get_best_compatible_version(root.iosVersion)
        root.version = info.version || ""

        if (!info.found || root.version.length === 0) {
            // FIXME: we need to disable the retry button in this case
            showError(qsTr("There is no compatible developer disk image available for this iOS version."))
            return
        }

        if (info.exists) {
            mountVersion(root.version)
            return
        }

        statusText = qsTr("Downloading compatible developer disk image...")

        //FIXME: downloadedVersion !== root.version
        //this will hang forever
        App.Helpers.connectOnce(DevImgsManager.image_download_finished, function(downloadedVersion, index, success, error) {
            DevImgsManager.handle_download_finished(downloadedVersion)

            if (downloadedVersion !== root.version)
                return

            if (!success) {
                showError(error && error.length > 0 ? error : qsTr("Failed to download compatible developer disk image."))
                return
            }

            mountVersion(root.version)
        })

        if (!DevImgsManager.download_image(root.version, 0))
            showError(qsTr("Failed to start developer disk image download."))
    }

    /* try to mount a specific version */
    function mountVersion(version) {
        statusText = qsTr("Mounting...")

        const locations = DevImgsManager.get_locations_for_version(version)
        if (!locations.exists || !locations.dmg || !locations.sig) {
            showError(qsTr("The developer disk image is missing. Please download it first."))
            return
        }

        App.Helpers.connectOnce(root.device.service_manager.dev_image_mounted, function(mountedVersion, success, isLocked) {
            if (!success) {
                if (isLocked) {
                    showError(qsTr("Failed to mount developer disk image.\nThe device appears to be locked. Please unlock the device and try again."))
                    return
                }

                showError(qsTr("Failed to mount developer disk image.\nPlease ensure the device is unlocked and using a genuine cable."))
                return
            }

            finishWithSuccess(true)
        })

        root.device.service_manager.mount_dev_image(version, locations.dmg, locations.sig)
    }

    /*
        waiting is sometimes required because services
        may not become available
        as soon as the img is mounted
    */
    function finishWithSuccess(wait) {
        statusText = qsTr("Developer disk image mounted.")
        stateView.viewState = StateView.State.Content
        successTimer.interval = wait ? 3000 : 250
        successTimer.restart()
    }

    onRejected: mountingCompleted(false)

    Timer {
        id: startTimer
        interval: 200
        repeat: false
        onTriggered: root.checkAndMount()
    }

    Timer {
        id: successTimer
        repeat: false
        onTriggered: {
            root.mountingCompleted(true)
            root.close()
        }
    }

    background: Rectangle {
        radius: 10
        color: palette.window
        border.color: Qt.rgba(0, 0, 0, 0.14)
        border.width: 1
    }

    contentItem: StateView {
        id: stateView
        autoSwitchContent: false
        retryable: true
        errorText: qsTr("Failed to mount developer disk image.")
        onRetryRequested: root.retry()

        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Item { Layout.fillHeight: true }

            Label {
                Layout.fillWidth: true
                text: root.statusText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: stateView.viewState === StateView.State.Content
            }

            Item { Layout.fillHeight: true }
        }
    }
}
