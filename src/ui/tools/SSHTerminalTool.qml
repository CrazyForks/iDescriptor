import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "../base"
import "../" as App

ToolWindow {
    id: root
    width: 760
    height: 500
    minimumWidth: 620
    minimumHeight: 420
    title: qsTr("SSH Terminal - iDescriptor")
    auto_close: false

    property string selectedType: ""
    property string selectedUniq: ""
    property string selectedIp: ""
    property string selectedUdid: ""
    property string selectedDeviceName: ""
    property bool selectedJailbrokenKnown: false
    property bool selectedJailbroken: false
    property string infoText: qsTr("Select a device to connect")
    property var sshProcessWindows: ({})

    ListModel { id: wiredDeviceModel }
    ListModel { id: networkDeviceModel }

    function deviceName(dev) {
        if (!dev)
            return qsTr("Unknown Device")
        if (dev.info && dev.info.marketing_name)
            return dev.info.marketing_name
        if (dev.info && dev.info.product_type)
            return dev.info.product_type
        return dev.text || qsTr("Unknown Device")
    }

    function isWirelessDevice(dev) {
        return dev && dev.info && dev.info.connection_type === "Wireless"
    }

    function isJailbroken(dev) {
        return !!(dev && dev.info && dev.info["Jailbroken"])
    }

    function rebuildWiredDevices() {
        wiredDeviceModel.clear()
        for (let i = 0; i < App.DeviceContext.devices.count; ++i) {
            const dev = App.DeviceContext.devices.get(i)
            wiredDeviceModel.append({
                text: root.deviceName(dev) + "\n" + dev.udid,
                deviceName: root.deviceName(dev),
                udid: dev.udid,
                uniq: root.isWirelessDevice(dev) && dev.info.WiFiAddress ? dev.info.WiFiAddress : dev.udid,
                ip: dev.info && dev.info.ipAddress ? dev.info.ipAddress : "",
                deviceType: root.isWirelessDevice(dev) ? "wireless" : "wired",
                jailbrokenKnown: true,
                jailbroken: root.isJailbroken(dev)
            })
        }
    }

    function normalizeNetworkDevice(mac, dev) {
        return {
            text: (dev.name || dev.deviceName || qsTr("Unknown device")) + "\n" + (dev.address || dev.ip || ""),
            deviceName: dev.name || dev.deviceName || qsTr("Unknown device"),
            udid: "",
            uniq: mac || dev.macAddress || dev.mac || dev.address || dev.ip || "",
            ip: dev.address || dev.ip || "",
            deviceType: "wireless",
            jailbrokenKnown: false,
            jailbroken: false
        }
    }

    function rebuildNetworkDevices() {
        networkDeviceModel.clear()
        const map = NetworkDeviceProvider.getNetworkDevices()
        if (!map)
            return

        const keys = Object.keys(map)
        for (let i = 0; i < keys.length; ++i) {
            const mac = keys[i]
            networkDeviceModel.append(normalizeNetworkDevice(mac, map[mac]))
        }
    }

    function selectDevice(item) {
        selectedType = item.deviceType
        selectedUniq = item.uniq
        selectedIp = item.ip || ""
        selectedUdid = item.udid || ""
        selectedDeviceName = item.deviceName || item.uniq
        selectedJailbrokenKnown = item.jailbrokenKnown
        selectedJailbroken = item.jailbroken
        infoText = qsTr("Ready to connect")
    }

    function selectModelDevice(modelData) {
        root.selectDevice({
            deviceType: modelData.deviceType,
            uniq: modelData.uniq,
            ip: modelData.ip || "",
            udid: modelData.udid || "",
            deviceName: modelData.deviceName || modelData.uniq,
            jailbrokenKnown: modelData.jailbrokenKnown,
            jailbroken: modelData.jailbroken
        })
    }

    function connectionLabel(item) {
        if (!item)
            return qsTr("Unknown")
        if (item.deviceType === "wired")
            return qsTr("USB")
        return qsTr("Network")
    }

    function deviceDetail(item) {
        if (!item)
            return ""
        if (item.deviceType === "wired")
            return item.udid || item.uniq || ""
        return item.ip || item.uniq || ""
    }

    function jailbreakStatus(item) {
        if (!item || !item.jailbrokenKnown)
            return qsTr("Jailbreak status unknown")
        return item.jailbroken ? qsTr("Jailbroken") : qsTr("Not detected as jailbroken")
    }

    function isSelected(item) {
        return !!item && root.selectedType === item.deviceType && root.selectedUniq === item.uniq
    }

    function resetSelection() {
        selectedType = ""
        selectedUniq = ""
        selectedIp = ""
        selectedUdid = ""
        selectedDeviceName = ""
        selectedJailbrokenKnown = false
        selectedJailbroken = false
        infoText = qsTr("Select a device to connect")
        wiredList.currentIndex = -1
        networkList.currentIndex = -1
    }

    function openTerminalProcess() {
        if (!selectedUniq) {
            infoText = qsTr("Please select a device first")
            noDeviceDialog.open()
            return
        }

        if (selectedType === "wireless" && !selectedIp) {
            infoText = qsTr("Selected network device is missing IP address. Please try again.")
            missingIpDialog.open()
            return
        }

        if (selectedJailbrokenKnown && !selectedJailbroken) {
            nonJailbrokenDialog.open()
            return
        }

        passwordDialog.open()
    }

    function openTerminalProcessNow(password) {
        const hostAddress = selectedType === "wired" ? "127.0.0.1" : selectedIp
        const processKey = selectedType + ":" + selectedUniq + ":" + hostAddress

        if (sshProcessWindows[processKey]) {
            const existing = sshProcessWindows[processKey]
            existing.show()
            existing.raise()
            existing.requestActivate()
            return
        }

        const comp = Qt.createComponent("./SSHProcessWindow.qml")
        if (comp.status !== Component.Ready) {
            console.error("Failed to load SSHProcessWindow:", comp.errorString())
            return
        }

        const win = comp.createObject(root, {
            udid: selectedUdid,
            device: null,
            auto_close: false,
            connectionType: selectedType,
            deviceName: selectedDeviceName || selectedUniq,
            deviceUdid: selectedUdid || selectedUniq,
            hostAddress: hostAddress,
            port: 22,
            rootPassword: password
        })

        if (!win) {
            console.error("Failed to create SSHProcessWindow:", comp.errorString())
            return
        }

        sshProcessWindows[processKey] = win
        win.closing.connect(function() {
            delete sshProcessWindows[processKey]
            win.destroy(0)
        })
        win.show()
        win.raise()
        win.requestActivate()
    }

    Component.onCompleted: {
        rebuildWiredDevices()
        rebuildNetworkDevices()
    }

    Connections {
        target: App.DeviceContext.devices
        function onCountChanged() {
            root.rebuildWiredDevices()
        }
    }

    Connections {
        target: NetworkDeviceProvider

        function onDeviceAdded(device) {
            const mac = device.macAddress || device.mac || ""
            networkDeviceModel.append(root.normalizeNetworkDevice(mac, device))
        }

        function onDeviceRemoved(deviceName) {
            for (let i = 0; i < networkDeviceModel.count; ++i) {
                const item = networkDeviceModel.get(i)
                if (item.deviceName === deviceName || item.uniq === deviceName) {
                    networkDeviceModel.remove(i, 1)
                    break
                }
            }
        }
    }

    MessageDialog {
        id: noDeviceDialog
        title: qsTr("No Device Selected")
        text: qsTr("Please select a device before trying to connect.")
    }

    MessageDialog {
        id: missingIpDialog
        title: qsTr("Missing IP Address")
        text: qsTr("The selected network device is missing an IP address. Please try again.")
    }

    MessageDialog {
        id: nonJailbrokenDialog
        title: qsTr("Device Not Jailbroken")
        text: qsTr("The selected device is not detected as jailbroken.\nSSH access may not be available.\n\nDo you want to continue anyway?")
        buttons: MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function(button, role) {
            if (button === MessageDialog.Yes)
                passwordDialog.open()
            else
                root.infoText = qsTr("Connection cancelled (device not jailbroken)")
        }
    }

    Dialog {
        id: passwordDialog
        modal: true
        anchors.centerIn: Overlay.overlay
        title: qsTr("SSH Root Password")
        standardButtons: Dialog.Ok | Dialog.Cancel
        onOpened: passwordField.text = ""
        onAccepted: {
            const fallbackPassword = settingsManager.default_jailbroken_root_password()
            root.openTerminalProcessNow(passwordField.text.length > 0 ? passwordField.text : fallbackPassword)
        }

        ColumnLayout {
            width: 360
            spacing: 10

            Label {
                Layout.fillWidth: true
                text: qsTr("Enter the root password. Leave it empty to use the default password.")
                wrapMode: Text.WordWrap
            }

            TextField {
                id: passwordField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: qsTr("Default password")
                focus: true
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Label {
                Layout.fillWidth: true
                text: qsTr("Choose an SSH target")
                color: App.Theme.text
                font.pixelSize: 22
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Select a jailbroken device, or connect directly by IP address.")
                color: App.Theme.textMuted
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 12

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120
                radius: App.Theme.sidebarCornerRadius
                color: App.Theme.softBg
                border.color: App.Theme.softBgBorder
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Connected Devices")
                            color: App.Theme.text
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Label {
                            text: qsTr("%1").arg(wiredDeviceModel.count)
                            color: App.Theme.textMuted
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 72

                        ListView {
                            id: wiredList
                            anchors.fill: parent
                            clip: true
                            model: wiredDeviceModel
                            currentIndex: -1
                            spacing: 8

                            delegate: Rectangle {
                                id: wiredRow
                                width: ListView.view.width
                                height: 70
                                radius: App.Theme.sidebarCornerRadius
                                color: root.isSelected(model)
                                       ? App.Theme.selection
                                       : (wiredMouse.containsMouse ? App.Theme.hover : App.Theme.controlFill)
                                border.color: root.isSelected(model) ? App.Theme.focus : App.Theme.controlStroke
                                border.width: 1

                                MouseArea {
                                    id: wiredMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        networkList.currentIndex = -1
                                        wiredList.currentIndex = index
                                        root.selectModelDevice(model)
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    RadioButton {
                                        checked: root.isSelected(model)
                                        onClicked: {
                                            networkList.currentIndex = -1
                                            wiredList.currentIndex = index
                                            root.selectModelDevice(model)
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Label {
                                                Layout.fillWidth: true
                                                text: model.deviceName || qsTr("Unknown Device")
                                                color: root.isSelected(model) ? App.Theme.textSelected : App.Theme.text
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }

                                            Label {
                                                text: root.connectionLabel(model)
                                                color: root.isSelected(model) ? App.Theme.textSelected : App.Theme.textMuted
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.deviceDetail(model)
                                            color: root.isSelected(model) ? App.Theme.textSelected : App.Theme.textMuted
                                            font.pixelSize: 12
                                            elide: Text.ElideMiddle
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.jailbreakStatus(model)
                                            color: root.isSelected(model)
                                                   ? App.Theme.textSelected
                                                   : (model.jailbroken ? App.Theme.accent : App.Theme.textMuted)
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: wiredDeviceModel.count === 0
                            text: qsTr("No connected devices")
                            color: App.Theme.textMuted
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120
                radius: App.Theme.sidebarCornerRadius
                color: App.Theme.softBg
                border.color: App.Theme.softBgBorder
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Network Devices")
                            color: App.Theme.text
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Label {
                            text: qsTr("%1").arg(networkDeviceModel.count)
                            color: App.Theme.textMuted
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 72

                        ListView {
                            id: networkList
                            anchors.fill: parent
                            clip: true
                            model: networkDeviceModel
                            currentIndex: -1
                            spacing: 8

                            delegate: Rectangle {
                                id: networkRow
                                width: ListView.view.width
                                height: 70
                                radius: App.Theme.sidebarCornerRadius
                                color: root.isSelected(model)
                                       ? App.Theme.selection
                                       : (networkMouse.containsMouse ? App.Theme.hover : App.Theme.controlFill)
                                border.color: root.isSelected(model) ? App.Theme.focus : App.Theme.controlStroke
                                border.width: 1

                                MouseArea {
                                    id: networkMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        wiredList.currentIndex = -1
                                        networkList.currentIndex = index
                                        root.selectModelDevice(model)
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    RadioButton {
                                        checked: root.isSelected(model)
                                        onClicked: {
                                            wiredList.currentIndex = -1
                                            networkList.currentIndex = index
                                            root.selectModelDevice(model)
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Label {
                                                Layout.fillWidth: true
                                                text: model.deviceName || qsTr("Unknown Device")
                                                color: root.isSelected(model) ? App.Theme.textSelected : App.Theme.text
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }

                                            Label {
                                                text: root.connectionLabel(model)
                                                color: root.isSelected(model) ? App.Theme.textSelected : App.Theme.textMuted
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.deviceDetail(model)
                                            color: root.isSelected(model) ? App.Theme.textSelected : App.Theme.textMuted
                                            font.pixelSize: 12
                                            elide: Text.ElideMiddle
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.jailbreakStatus(model)
                                            color: root.isSelected(model)
                                                   ? App.Theme.textSelected
                                                   : (model.jailbroken ? App.Theme.accent : App.Theme.textMuted)
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: networkDeviceModel.count === 0
                            text: qsTr("No network devices")
                            color: App.Theme.textMuted
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 76
            radius: App.Theme.sidebarCornerRadius
            color: App.Theme.softBg
            border.color: App.Theme.softBgBorder
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Manual IP Connection")
                        color: App.Theme.text
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Use this when the device is reachable but not listed above.")
                        color: App.Theme.textMuted
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                TextField {
                    id: manualIpEdit
                    Layout.preferredWidth: Math.min(220, Math.max(150, root.width * 0.28))
                    placeholderText: qsTr("192.168.1.10")
                }

                Button {
                    text: qsTr("Connect by IP")
                    enabled: manualIpEdit.text.trim().length > 0
                    onClicked: {
                        const ip = manualIpEdit.text.trim()
                        if (ip.length === 0) {
                            root.infoText = qsTr("Please enter an IP address")
                            missingIpDialog.open()
                            return
                        }

                        wiredList.currentIndex = -1
                        networkList.currentIndex = -1
                        root.selectedType = "wireless"
                        root.selectedUniq = ip
                        root.selectedIp = ip
                        root.selectedUdid = ""
                        root.selectedDeviceName = ip
                        root.selectedJailbrokenKnown = false
                        root.selectedJailbroken = false
                        root.infoText = qsTr("Ready to connect")
                        root.openTerminalProcess()
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 44

            RowLayout {
                anchors.fill: parent
                spacing: 10

                Label {
                    Layout.fillWidth: true
                    text: root.selectedUniq
                          ? qsTr("%1 selected").arg(root.selectedDeviceName || root.selectedUniq)
                          : root.infoText
                    color: App.Theme.textMuted
                    elide: Text.ElideMiddle
                }

                Button {
                    text: root.selectedUniq ? qsTr("Connect") : qsTr("Choose a device")
                    enabled: !!root.selectedUniq
                    onClicked: root.openTerminalProcess()
                }
            }
        }
    }
}
