pragma Singleton

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import "." as App
import "./base"

Window {
    id: root
    width: 400
    height: 500
    minimumWidth: 400
    minimumHeight: 500
    title: qsTr("Settings - iDescriptor")
    visible: false
    modality: Qt.ApplicationModal

    property bool dirty: false
    property bool restartRequired: false
    readonly property var backend: typeof settingsManager !== "undefined" ? settingsManager : null

    property string downloadPath: ""
    property string backupRootPath: ""
    property int wireless_file_server_port: 8080
    property bool unmount_ifuse_on_exit: false
    property bool auto_check_updates: true
    property bool auto_enable_wifi_connections: true
    property string theme: "System Default"
    property string language: "en"
    property bool auto_raise_window: true
    property bool switch_to_new_device: true
    property bool auto_connect_wireless_devices: true
    property int connection_timeout: 30
    property bool use_unsecure_backend: false
    property string default_jailbroken_root_password: "alpine"
    property real icon_size_base_multiplier: 1.0
    property int airplay_fps: 60
    property bool airplay_no_hold: true
    property bool airplay_use_legacy_ports: true
    property bool show_v4l2: false

    function open() {
        loadSettings()
        show()
        raise()
        requestActivate()
    }

    function markDirty(restart) {
        dirty = true
        if (restart)
            restartRequired = true
    }

    function backendValue(name, fallback) {
        if (!backend || typeof backend[name] !== "function")
            return fallback
        return backend[name]()
    }

    function callBackend(name) {
        if (!backend || typeof backend[name] !== "function")
            return

        const args = Array.prototype.slice.call(arguments, 1)
        backend[name].apply(backend, args)
    }

    function normalizeLanguage(value) {
        const normalized = String(value || "en").trim().toLowerCase()
        if (normalized === "german" || normalized.indexOf("de") === 0)
            return "de"
        return "en"
    }

    function applyLanguage() {
        if (typeof QmlUtils !== "undefined" && QmlUtils && typeof QmlUtils.set_language === "function")
            QmlUtils.set_language(language)
    }

    function loadSettings() {
        downloadPath = backendValue("dev_disk_img_path", "")
        backupRootPath = backendValue("backup_root_path", "")
        wireless_file_server_port = backendValue("wireless_file_server_port", 8080)
        unmount_ifuse_on_exit = backendValue("unmount_ifuse_on_exit", false)
        auto_check_updates = backendValue("auto_check_updates", true)
        auto_enable_wifi_connections = backendValue("auto_enable_wifi_connections", true)
        theme = backendValue("theme", "System Default")
        language = normalizeLanguage(backendValue("language", "en"))
        auto_raise_window = backendValue("auto_raise_window", true)
        switch_to_new_device = backendValue("switch_to_new_device", true)
        auto_connect_wireless_devices = backendValue("auto_connect_wireless_devices", true)
        connection_timeout = backendValue("connection_timeout", 30)
        use_unsecure_backend = backendValue("use_unsecure_backend", false)
        default_jailbroken_root_password = backendValue("default_jailbroken_root_password", "alpine")
        icon_size_base_multiplier = backendValue("icon_size_base_multiplier", 1.0)
        airplay_fps = backendValue("airplay_fps", 60)
        airplay_no_hold = backendValue("airplay_no_hold", true)
        airplay_use_legacy_ports = backendValue("airplay_use_legacy_ports", true)
        show_v4l2 = backendValue("show_v4l2", false)
        dirty = false
        restartRequired = false
        applyLanguage()
    }

    function applySettings() {
        callBackend("set_dev_disk_img_path", downloadPath)
        callBackend("set_backup_root_path", backupRootPath)
        callBackend("set_wireless_file_server_port", wireless_file_server_port)
        callBackend("set_unmount_ifuse_on_exit", unmount_ifuse_on_exit)
        callBackend("set_auto_check_updates", auto_check_updates)
        callBackend("set_auto_enable_wifi_connections", auto_enable_wifi_connections)
        callBackend("set_theme", theme)
        callBackend("set_language", language)
        applyLanguage()
        callBackend("set_auto_raise_window", auto_raise_window)
        callBackend("set_switch_to_new_device", switch_to_new_device)
        callBackend("set_auto_connect_wireless_devices", auto_connect_wireless_devices)
        callBackend("set_connection_timeout", connection_timeout)
        callBackend("set_use_unsecure_backend", use_unsecure_backend)
        callBackend("set_default_jailbroken_root_password", default_jailbroken_root_password)
        callBackend("set_icon_size_base_multiplier", icon_size_base_multiplier)
        callBackend("set_airplay_fps", airplay_fps)
        callBackend("set_airplay_no_hold", airplay_no_hold)
        callBackend("set_airplay_use_legacy_ports", airplay_use_legacy_ports)
        callBackend("set_show_v4l2", show_v4l2)

        dirty = false
        appliedDialog.text = restartRequired
                ? qsTr("Settings applied. Please restart the application for changes to take effect.")
                : qsTr("Settings applied.")
        restartRequired = false
        appliedDialog.open()
    }

    function reset_to_defaults() {
        callBackend("reset_to_defaults")
        loadSettings()
        dirty = true
    }

    Component.onCompleted: loadSettings()

    FolderDialog {
        id: downloadPathDialog
        title: qsTr("Select Download Directory")
        onAccepted: {
            root.downloadPath = QmlUtils.url_to_path(selectedFolder)
            root.markDirty(false)
        }
    }

    FolderDialog {
        id: backupRootPathDialog
        title: qsTr("Select Backup Directory")
        onAccepted: {
            root.backupRootPath = QmlUtils.url_to_path(selectedFolder)
            root.markDirty(false)
        }
    }

    MessageDialog {
        id: appliedDialog
        title: qsTr("Settings")
    }

    MessageDialog {
        id: insecureBackendDialog
        title: qsTr("Warning")
        text: qsTr("Enabling this will not encrypt your Apple account, which is a security risk. Are you sure you want to enable this?")
        buttons: MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function(button, role) {
            if (button === MessageDialog.Yes) {
                root.use_unsecure_backend = true
                root.markDirty(true)
            } else {
                root.use_unsecure_backend = false
            }
        }
    }

    MessageDialog {
        id: resetDialog
        title: qsTr("Reset Settings")
        text: qsTr("Are you sure you want to reset all settings to their default values?")
        buttons: MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function(button, role) {
            if (button === MessageDialog.Yes)
                root.reset_to_defaults()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: palette.window
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: Math.min(560, root.width - 28)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 22

                Item { Layout.preferredHeight: 12 }

                SettingsSection {
                    title: qsTr("General")

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Label {
                            text: qsTr("Download Path")
                            Layout.preferredWidth: 175
                        }

                        TextField {
                            Layout.fillWidth: true
                            text: root.downloadPath
                            readOnly: true
                            selectByMouse: true
                        }

                        Button {
                            text: qsTr("Browse")
                            onClicked: downloadPathDialog.open()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Label {
                            text: qsTr("Backup Path")
                            Layout.preferredWidth: 175
                        }

                        TextField {
                            Layout.fillWidth: true
                            text: root.backupRootPath
                            readOnly: true
                            selectByMouse: true
                        }

                        Button {
                            text: qsTr("Browse")
                            onClicked: backupRootPathDialog.open()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Label {
                            text: qsTr("Wireless File Server Port")
                            Layout.preferredWidth: 175
                        }

                        SpinBox {
                            from: 1024
                            to: 65535
                            value: root.wireless_file_server_port
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("The starting port for the wireless file server. If this port is unavailable, it will try the next 10 ports.")
                            onValueModified: {
                                root.wireless_file_server_port = value
                                root.markDirty(false)
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    CheckBox {
                        visible: Qt.platform.os !== "osx" && Qt.platform.os !== "darwin"
                        text: qsTr("Unmount iFuse drives on exit")
                        checked: root.unmount_ifuse_on_exit
                        onToggled: {
                            root.unmount_ifuse_on_exit = checked
                            root.markDirty(false)
                        }
                    }

                    CheckBox {
                        text: qsTr("Automatically check for updates")
                        checked: root.auto_check_updates
                        onToggled: {
                            root.auto_check_updates = checked
                            root.markDirty(false)
                        }
                    }

                    CheckBox {
                        text: qsTr("Automatically enable Wi-Fi connections")
                        checked: root.auto_enable_wifi_connections
                        onToggled: {
                            root.auto_enable_wifi_connections = checked
                            root.markDirty(false)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Label {
                            text: qsTr("Theme")
                            Layout.preferredWidth: 175
                        }

                        ComboBox {
                            model: [qsTr("System Default")]
                            currentIndex: 0
                            onActivated: {
                                root.theme = currentText
                                root.markDirty(false)
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Label {
                            text: qsTr("Language")
                            Layout.preferredWidth: 175
                        }

                        ComboBox {
                            textRole: "label"
                            valueRole: "value"
                            model: [
                                { value: "en", label: qsTr("English") },
                                { value: "de", label: qsTr("German") }
                            ]
                            currentIndex: Math.max(0, indexOfValue(root.language))
                            onActivated: {
                                root.language = currentValue
                                root.markDirty(true)
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }

                SettingsSection {
                    title: qsTr("Device Connection")

                    CheckBox {
                        text: qsTr("Auto-raise main window on device connection")
                        checked: root.auto_raise_window
                        onToggled: {
                            root.auto_raise_window = checked
                            root.markDirty(false)
                        }
                    }

                    CheckBox {
                        text: qsTr("Switch to newly connected device")
                        checked: root.switch_to_new_device
                        onToggled: {
                            root.switch_to_new_device = checked
                            root.markDirty(false)
                        }
                    }

                    CheckBox {
                        text: qsTr("Automatically connect to wireless devices")
                        checked: root.auto_connect_wireless_devices
                        onToggled: {
                            root.auto_connect_wireless_devices = checked
                            root.markDirty(false)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Label {
                            text: qsTr("Connection Timeout")
                            Layout.preferredWidth: 175
                        }

                        SpinBox {
                            from: 5
                            to: 60
                            value: root.connection_timeout
                            textFromValue: function(value, locale) { return value + qsTr(" seconds") }
                            valueFromText: function(text, locale) { return parseInt(text) || 5 }
                            onValueModified: {
                                root.connection_timeout = value
                                root.markDirty(false)
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }

                SettingsSection {
                    title: qsTr("Security")

                    CheckBox {
                        text: qsTr("Use unsecure backend for app store (ipatool)")
                        checked: root.use_unsecure_backend
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Enabling this may put your Apple account at risk but you do not have to deal with Apple keychain.")
                        onToggled: {
                            if (checked && !root.use_unsecure_backend) {
                                insecureBackendDialog.open()
                            } else {
                                root.use_unsecure_backend = checked
                                root.markDirty(true)
                            }
                        }
                    }
                }

                SettingsSection {
                    title: qsTr("Jailbroken")

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Label {
                            text: qsTr("Default Root Password")
                            Layout.preferredWidth: 175
                        }

                        TextField {
                            Layout.preferredWidth: 100
                            text: root.default_jailbroken_root_password
                            echoMode: TextInput.PasswordEchoOnEdit
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Default password used for SSH root authentication on jailbroken devices. Default is 'alpine'.")
                            onTextEdited: {
                                root.default_jailbroken_root_password = text
                                root.markDirty(false)
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }

                SettingsSection {
                    title: qsTr("AirPlay")

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Label {
                            text: qsTr("Fps")
                            Layout.preferredWidth: 175
                        }

                        ComboBox {
                            model: ["24", "30", "60", "120"]
                            currentIndex: Math.max(0, model.indexOf(String(root.airplay_fps)))
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Set the fps for AirPlay. Go with 30 fps if you have an older device.")
                            onActivated: {
                                root.airplay_fps = Number(currentText)
                                root.markDirty(false)
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    CheckBox {
                        text: qsTr("Allow New Connections to Take Over")
                        checked: root.airplay_no_hold
                        onToggled: {
                            root.airplay_no_hold = checked
                            root.markDirty(false)
                        }
                    }

                    CheckBox {
                        visible: Qt.platform.os === "linux"
                        text: qsTr("Use legacy ports")
                        checked: root.airplay_use_legacy_ports
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Use legacy ports, refer to AIRPLAY.md for more information.")
                        onToggled: {
                            root.airplay_use_legacy_ports = checked
                            root.markDirty(false)
                        }
                    }

                    CheckBox {
                        visible: Qt.platform.os === "linux"
                        text: qsTr("Show V4L2 Button on AirPlay Widget")
                        checked: root.show_v4l2
                        onToggled: {
                            root.show_v4l2 = checked
                            root.markDirty(false)
                        }
                    }
                }

                SettingsSection {
                    title: qsTr("Miscellaneous")

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Label {
                            text: qsTr("Icon Size Base Multiplier")
                            Layout.preferredWidth: 175
                        }

                        SpinBox {
                            id: iconMultiplierSpin
                            from: 10
                            to: 50
                            stepSize: 1
                            value: Math.round(root.icon_size_base_multiplier * 10)
                            textFromValue: function(value, locale) { return (value / 10).toFixed(1) + "x" }
                            valueFromText: function(text, locale) { return Math.round(Number(text.replace("x", "")) * 10) || 10 }
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Adjust the base multiplier for icon sizes. Requires restart to take effect.")
                            onValueModified: {
                                root.icon_size_base_multiplier = value / 10
                                root.markDirty(true)
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("iDescriptor\nA free, open-source, and cross-platform iDevice management tool.")
                    color: "#8a8a8e"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                Item { Layout.preferredHeight: 18 }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 58
            color: palette.window
            border.color: Qt.rgba(0, 0, 0, 0.10)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                Button {
                    text: qsTr("Check for Updates")
                    onClicked: App.Updater.checkForUpdates(true)
                }

                Button {
                    text: qsTr("Reset Settings")
                    onClicked: resetDialog.open()
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: qsTr("Apply")
                    enabled: root.dirty
                    onClicked: root.applySettings()
                }
            }
        }
    }

    component SettingsSection: SectionBox {
        Layout.fillWidth: true
    }
}
