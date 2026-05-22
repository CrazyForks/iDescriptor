import QtQuick
import QtQuick.Controls 
import QtQuick.Layouts 
import "../base"

ToolWindow {
    id: root
    width: 600
    height: 400
    visible: true
    title: qsTr("Cable Information - iDescriptor")


    property string errorText: ""
    property string statusText: qsTr("Analyzing cable...")
    property color statusColor: "#000000"
    property string descriptionText: qsTr("Please wait while we analyze the connected cable.")
    property bool isTypeC: false
    property bool isGenuine: false
    property bool isFakeInfo: false
    property bool isConnected: true
    property bool isOldDevice: false

    ListModel { id: infoModel }

    function normalizeString(s) { return (s && s.length) ? s : "Error" }
    function normalizeInt(i) { return i ? i : 0}

    function initCableInfo() {
        if (!root.device) {
            errorText = qsTr("Something went wrong (no device ?)")
            stateView.viewState = StateView.State.Error
            return
        }
        stateView.viewState = StateView.State.Loading
        errorText = ""
        statusText = qsTr("Analyzing cable...")
        descriptionText = qsTr("Please wait while we analyze the connected cable.")
        root.device.service_manager.get_cable_info()
    }

    function parseAndUpdate(raw) {
        let obj = raw
        if (typeof raw === "string") {
            if (raw.length === 0) {
                errorText = qsTr("No cable information retrieved.")
                stateView.viewState = StateView.State.Error
                return
            }
            try {
                obj = JSON.parse(raw)
            } catch (e) {
                errorText = qsTr("Failed to parse cable information.")
                stateView.viewState = StateView.State.Error
                return
            }
        }
        if (!obj || typeof obj !== "object") {
            errorText = qsTr("Failed to parse cable information.")
            stateView.viewState = StateView.State.Error
            return
        }

        isOldDevice = obj.ConnectionActive === undefined
        isConnected = !!obj.ConnectionActive

        const manufacturer = normalizeString(obj.IOAccessoryAccessoryManufacturer)
        const modelNumber = normalizeString(obj.IOAccessoryAccessoryModelNumber)
        const accessoryName = normalizeString(obj.IOAccessoryAccessoryName)
        const serialNumber = normalizeString(obj.IOAccessoryAccessorySerialNumber)
        const interfaceModuleSerial = normalizeString(obj.IOAccessoryInterfaceModuleSerialNumber)
        const triStarClass = normalizeString(obj.TriStarICClass)

        isTypeC = accessoryName.toLowerCase().indexOf("usb-c") !== -1 || triStarClass.indexOf("1612") !== -1

        const preGenuineCheck = manufacturer.toLowerCase().indexOf("apple") !== -1
            && modelNumber.length > 0
            && accessoryName.length > 0

        // FIXME: hardcoded
        let actuallyTypeC = true
        if (root.device && root.device.deviceInfo && root.device.deviceInfo.batteryInfo) {
            actuallyTypeC = root.device.deviceInfo.batteryInfo.usbConnectionType === "USB_TYPEC"
        }
        if (isTypeC && !actuallyTypeC) {
            isFakeInfo = true
        } else {
            isFakeInfo = false
        }
        isGenuine = isTypeC ? (actuallyTypeC && preGenuineCheck) : preGenuineCheck

        descriptionText = qsTr("Please note that this check may not be absolute guarantee of authenticity.")
        if (isGenuine) {
            statusText = qsTr("Genuine %1").arg(isTypeC
                ? qsTr("USB-C to Lightning Cable")
                : qsTr("Lightning Cable"))
            statusColor = "#28a745"
        } else {
            statusText = qsTr("Third-party Cable")
            statusColor = "#dc3545"
            if (isFakeInfo) {
                descriptionText = qsTr("The cable reports false information. It is most likely a fake cable.")
            }
        }

        infoModel.clear()
        function pushRow(label, value) {
            if (value && value.length !== 0)
                infoModel.append({ label: label, value: value })
        }

        if (!isConnected && !isOldDevice) {
            errorText = qsTr("Device does not seem to be connected to any cable.")
            stateView.viewState = StateView.State.Error
            return
        }

        pushRow(qsTr("Name:"), accessoryName)
        pushRow(qsTr("Manufacturer:"), manufacturer)
        pushRow(qsTr("Model:"), modelNumber)
        pushRow(qsTr("Serial Number:"), serialNumber)
        pushRow(qsTr("Interface Module:"), interfaceModuleSerial)

        pushRow(qsTr("Cable Type:"), isTypeC
            ? qsTr("USB-C to Lightning")
            : qsTr("Lightning to USB-A"))

        const currentLimit = normalizeInt(obj.IOAccessoryUSBCurrentLimit)
        const chargingVoltage = normalizeInt(obj.IOAccessoryUSBChargingVoltage)
        if (currentLimit > 0) pushRow(qsTr("Current Limit:"), qsTr("%1 mA").arg(currentLimit))
        if (chargingVoltage > 0) pushRow(qsTr("Charging Voltage:"), qsTr("%1 mV").arg(chargingVoltage))

        const connectString = normalizeString(obj.IOAccessoryUSBConnectString)
        const connectType = normalizeInt(obj.IOAccessoryUSBConnectType)
        if (connectString.length || connectType) {
            pushRow(qsTr("Connection:"), qsTr("%1 (Type %2)").arg(connectString).arg(connectType))
        }

        pushRow(qsTr("Controller:"), triStarClass)

        const activeTransports = Array.isArray(obj.TransportsActive) ? obj.TransportsActive : []
        const supportedTransports = Array.isArray(obj.TransportsSupported) ? obj.TransportsSupported : []
        if (activeTransports.length) pushRow(qsTr("Active Transports:"), activeTransports.join(", "))
        if (supportedTransports.length) pushRow(qsTr("Supported Transports:"), supportedTransports.join(", "))

        stateView.viewState = StateView.State.Content
    }

    Connections {
        target: root.device.service_manager
        function onCable_info_retrieved(response) {
            parseAndUpdate(response)
        }
    }

    Component.onCompleted: Qt.callLater(initCableInfo)


    StateView {
        id: stateView
        anchors.fill: parent
        errorText: root.errorText
        retryable: true
        onRetryRequested: initCableInfo()

        contentItem : ColumnLayout {
            anchors.fill: parent
            spacing: 20

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Label {
                    text: statusText
                    color: statusColor
                    font.pixelSize: 18
                    Layout.fillWidth: true
                }

                Button {
                    text: qsTr("Re-analyze")
                    onClicked: initCableInfo()
                }
            }

            Label {
                text: descriptionText
                font.pixelSize: 9
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            GroupBox {
                title: qsTr("Cable Information")
                Layout.fillWidth: true
                Layout.fillHeight: true

                ScrollView {
                    anchors.fill: parent

                    ColumnLayout {
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: infoModel
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Label {
                                    text: model.label
                                    Layout.preferredWidth: 160
                                    Layout.alignment: Qt.AlignTop
                                    // FIXME
                                    color: "black"
                                }
                                Label {
                                    text: model.value
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    color: "black"

                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
