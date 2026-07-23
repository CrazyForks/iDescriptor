pragma Singleton
import QtQml
import QtQml.Models
import QtQuick
import iDescriptor

QtObject {
    id: root
    property ListModel devices: ListModel {}
    property ListModel recoveryDevices: ListModel {}
    property ListModel pendingDevices: ListModel {}
    property string currentDeviceUdid : ""
    property string currentRecoveryDeviceId : ""
    property string currentPendingDeviceUdid: ""
    property int currentTab: 0
    property bool showWelcomePage : true
    // Record<normalized MAC, { ip, selectOnSuccess }>
    property var wirelessConnectionAttempts: ({})
    // Record<UDID, attempt token>
    property var wifiEnableAttempts: ({})
    property int wifiEnableAttemptToken: 0

    signal deviceRemoved(string udid)
    signal deviceAdded(string udid, string mac)
    signal deviceAlreadyExistsMAC(string mac)
    signal initStarted(string mac)
    signal noPairingFileForWirelessDevice(string mac)
    signal pairingFailed(string udid)

    function init() {
        /* core is a global obj set from rust side*/
        core.init()
    }

    function getDevice(udid) {
        for (let i = 0; i < devices.count; i++) {
            const device = devices.get(i)
            if (device.udid === udid) {
                return device
            }
        }
        return null
    }

    function getDeviceCount() {
        return devices.count + recoveryDevices.count
    }

    function getVisibleDeviceCount() {
        return devices.count + recoveryDevices.count + pendingDevices.count
    }

    function selectConnectedDevice(udid) {
        root.currentDeviceUdid = udid
        root.currentRecoveryDeviceId = ""
        root.currentPendingDeviceUdid = ""
        root.showWelcomePage = false
    }

    function selectRecoveryDevice(id) {
        root.currentDeviceUdid = ""
        root.currentRecoveryDeviceId = id
        root.currentPendingDeviceUdid = ""
        root.showWelcomePage = false
    }

    function selectPendingDevice(udid) {
        root.currentDeviceUdid = ""
        root.currentRecoveryDeviceId = ""
        root.currentPendingDeviceUdid = udid
        root.showWelcomePage = false
    }

    function selectWelcomePage() {
        root.currentDeviceUdid = ""
        root.currentRecoveryDeviceId = ""
        root.currentPendingDeviceUdid = ""
        root.showWelcomePage = true
    }

    function getRecoveryDevice(id) {
        for (let i = 0; i < recoveryDevices.count; i++) {
            const device = recoveryDevices.get(i)
            if (device.id === id) {
                return device
            }
        }
        return null
    }

    function getPendingDevice(udid) {
        for (let i = 0; i < pendingDevices.count; i++) {
            const device = pendingDevices.get(i)
            if (device.udid === udid)
                return device
        }
        return null
    }

    function removePendingDevice(udid, updateSelection) {
        for (let i = 0; i < pendingDevices.count; i++) {
            if (pendingDevices.get(i).udid === udid) {
                pendingDevices.remove(i)
                break
            }
        }

        if (root.currentPendingDeviceUdid === udid)
            root.currentPendingDeviceUdid = ""

        if (updateSelection !== false)
            root.selectFallbackDevice()
        else
            root.showWelcomePage = root.getVisibleDeviceCount() === 0
    }

    function selectFallbackDevice() {
        if (root.currentDeviceUdid && root.getDevice(root.currentDeviceUdid)) {
            root.selectConnectedDevice(root.currentDeviceUdid)
            return
        }

        if (root.currentRecoveryDeviceId && root.getRecoveryDevice(root.currentRecoveryDeviceId)) {
            root.selectRecoveryDevice(root.currentRecoveryDeviceId)
            return
        }

        if (root.currentPendingDeviceUdid && root.getPendingDevice(root.currentPendingDeviceUdid)) {
            root.selectPendingDevice(root.currentPendingDeviceUdid)
            return
        }

        if (devices.count > 0) {
            root.selectConnectedDevice(devices.get(0).udid)
        } else if (recoveryDevices.count > 0) {
            root.selectRecoveryDevice(recoveryDevices.get(0).id)
        } else if (pendingDevices.count > 0) {
            root.selectPendingDevice(pendingDevices.get(0).udid)
        } else {
            root.selectWelcomePage()
        }
    }

    function getDeviceByMacAddress(mac) {
        const normalizedMac = root.normalizeMacAddress(mac)
        if (normalizedMac.length !== 12)
            return null
        for (let i = 0; i < devices.count; i++) {
            const device = devices.get(i)
            if (root.normalizeMacAddress(device.info["WiFiAddress"]) === normalizedMac) {
                return device
            }
        }
        return null
    }

    function normalizeMacAddress(mac) {
        return String(mac || "").replace(/[^0-9a-f]/gi, "").toLowerCase()
    }

    function enableWifiConnections(device, dialogParent) {
        if (!device || !device.udid || !device.service_manager) {
            console.log("WTF")
            return false
        }

        const udid = String(device.udid)
        if (root.wifiEnableAttempts[udid])
            return false

        const serviceManager = device.service_manager
        const deviceName = device.info && device.info.marketing_name
                ? device.info.marketing_name : qsTr("this device")
        const attemptToken = ++root.wifiEnableAttemptToken
        root.wifiEnableAttempts[udid] = attemptToken

        Helpers.connectOnce(serviceManager.enableWifiConnectionsResult, function(success) {
            if (root.wifiEnableAttempts[udid] !== attemptToken)
                return

            delete root.wifiEnableAttempts[udid]

            if (success) {
                settingsManager.set_has_seen_device(udid, true)
                Helpers.messageBox(
                    dialogParent,
                    qsTr("Wi-Fi Connections Enabled"),
                    qsTr("Wi-Fi connections are now enabled for %1. You can disconnect the cable and use this device wirelessly.").arg(deviceName)
                )
            } else {
                Helpers.messageBox(
                    dialogParent,
                    qsTr("Unable to Enable Wi-Fi Connections"),
                    qsTr("Wi-Fi connections could not be enabled for %1. Keep the device connected, unlocked, and trusted, then try again.").arg(deviceName)
                )
            }
        })

        serviceManager.enable_wifi_connections()
        return true
    }

    function networkDeviceForMac(mac) {
        const normalizedMac = root.normalizeMacAddress(mac)
        if (normalizedMac.length !== 12)
            return null

        const networkDevices = NetworkDeviceProvider.getNetworkDevices()
        const keys = Object.keys(networkDevices)
        for (let i = 0; i < keys.length; ++i) {
            const key = keys[i]
            const networkDevice = networkDevices[key]
            const candidateMac = networkDevice.macAddress || networkDevice.mac || key
            if (root.normalizeMacAddress(candidateMac) === normalizedMac)
                return networkDevice
        }

        return null
    }

    function upgradeWiredDeviceToWireless(mac, selectOnSuccess) {
        if (!settingsManager.upgrade_to_wireless_on_disconnect())
            return

        const networkDevice = root.networkDeviceForMac(mac)
        if (!networkDevice)
            return

        const ip = networkDevice.address || networkDevice.ip || ""
        if (!ip)
            return

        root.tryToConnectToNetworkDevice(mac, ip, selectOnSuccess)
    }

    function finishWirelessConnectionAttempt(mac) {
        const key = root.normalizeMacAddress(mac)
        const attempt = root.wirelessConnectionAttempts[key]
        if (attempt)
            delete root.wirelessConnectionAttempts[key]
        return attempt || null
    }

    // receives path of pairing file
    function tryToConnectToNetworkDeviceCustom(ip, path) {
        console.log("QML: Trying to connect to network device with IP:", ip, "and pairing file path:", path);
        core.init_wireless_device_custom(ip, path)
    }

    function tryToConnectToNetworkDevice(mac, ip, select_on_success) {
        console.log("QML: Trying to connect to network device with MAC:", mac, "IP:", ip);

        const existingDevice = root.getDeviceByMacAddress(mac);

        if (existingDevice) {
            console.log("Device with MAC:", mac, "already exists. Emitting deviceAlreadyExistsMAC event");
            root.deviceAlreadyExistsMAC(mac);
            if (select_on_success) {
                console.log("Setting existing device as current selection");
                root.selectConnectedDevice(existingDevice.udid);
            }
            return;
        }

        const key = root.normalizeMacAddress(mac)
        const existingAttempt = root.wirelessConnectionAttempts[key]
        if (existingAttempt) {
            // A manual request upgrades an automatic attempt without starting another connection.
            if (select_on_success)
                existingAttempt.selectOnSuccess = true
            return;
        }

        root.wirelessConnectionAttempts[key] = {
            ip: ip,
            selectOnSuccess: !!select_on_success
        }
        core.init_wireless_device(ip, mac);
        root.initStarted(mac);
    }

    function removeDevice(udid) {
        for (let i = 0; i < devices.count; i++) {
            const device = devices.get(i)
            if (device.udid === udid) {
                devices.remove(i)
                core.remove_device(udid)
                // force garbage collection
                // this may not work due to rust side being async,
                // but no harm in trying
                Helpers.setTimeout(()=> {
                    gc()
                },1000)
                break
            }
        }
    }



    // workaround to use connections inside a QtObject
    property var _connections : Connections {
        target: core

        function onDeviceEvent(eventType, udid, info) {
            console.log("Device event:", eventType, udid, JSON.stringify(info))

            switch (eventType) {
                /* Device added */
                case 1:
                    root.removePendingDevice(udid, false)
                    const service_manager = serviceFactory.create_service_manager(udid, info.ios_version_major)
                    const sb_client = serviceFactory.create_springboard_services_client(udid)
                    const text = `${info.marketing_name} / ${udid.slice(0,10)}...`
                    const mac = info["WiFiAddress"]
                    const wirelessAttempt = info.is_wireless
                            ? root.finishWirelessConnectionAttempt(mac) : null
                    devices.append(
                        {
                            udid: udid,
                            info: info,
                            text,
                            service_manager,
                            sb_client,
                            // default to info section
                            currentSection: 0,
                            afcClient: serviceFactory.create_afc_client(udid, false)
                        }
                    )
                    root.deviceAdded(udid, mac)
                    // Automatic wireless connections stay in the background. Wired and
                    // custom pairing-file connections preserve their existing behavior.
                    if (!wirelessAttempt || wirelessAttempt.selectOnSuccess)
                        root.selectConnectedDevice(udid)
                    break;
                /* Device removed */
                case 2:
                    delete root.wifiEnableAttempts[udid]
                    let removedMac = ""
                    let removedDeviceWasWireless = false
                    const removedDeviceWasSelected = root.currentDeviceUdid === udid

                    // FIXME: find an O(1) solution
                    for (let i = 0; i < devices.count; i++) {
                        const device = devices.get(i)
                        if (device.udid === udid) {
                            removedMac = device.info["WiFiAddress"] || ""
                            removedDeviceWasWireless = !!device.info.is_wireless
                            devices.remove(i)
                            break
                        }
                    }
                    if (root.currentDeviceUdid === udid)
                        root.currentDeviceUdid = ""
                    root.removePendingDevice(udid, false)
                    root.deviceRemoved(udid)
                    root.selectFallbackDevice()
                    if (!removedDeviceWasWireless && removedMac) {
                        Qt.callLater(function() {
                            root.upgradeWiredDeviceToWireless(
                                removedMac,
                                removedDeviceWasSelected
                            )
                        })
                    }
                    break;
                /* Pending device added */
                case 3:
                    if (root.getDevice(udid) || root.getPendingDevice(udid))
                        break

                    pendingDevices.append({
                        udid: udid,
                        text: qsTr("Pairing…")
                    })
                    root.showWelcomePage = false
                    if (!root.currentDeviceUdid
                            && !root.currentRecoveryDeviceId
                            && !root.currentPendingDeviceUdid) {
                        root.selectPendingDevice(udid)
                    }
                    break;
                /* Pending device removed */
                case 4:
                    if (root.getPendingDevice(udid)) {
                        root.removePendingDevice(udid, true)
                        root.pairingFailed(udid)
                    }
                    break;
                default:

            }
            /* force garbage collection otherwise
            things get cleaned up after a long time */
            gc();
        }


        function onRecoveryDeviceEvent(eventType, id, info) {
            console.log("Recovery device event:", eventType, id, JSON.stringify(info))

            switch (eventType) {
                /* Recovery device added */
                case 1:

                    const name = info.marketing_name;
                    const entry = { id, info: info, text: name }
                    recoveryDevices.append(entry)

                    root.showWelcomePage = false
                    if (!root.currentDeviceUdid
                            && !root.currentRecoveryDeviceId
                            && !root.currentPendingDeviceUdid)
                        root.selectRecoveryDevice(id)
                    break;
                /* Recovery device removed */
                case 2:
                    for (let i = 0; i < recoveryDevices.count; i++) {
                        const device = recoveryDevices.get(i)
                        if (device.id === id) {
                            recoveryDevices.remove(i)
                            break
                        }
                    }
                    if (root.currentRecoveryDeviceId === id)
                        root.currentRecoveryDeviceId = ""
                    root.selectFallbackDevice()
                    break;
            }
            /* force garbage collection otherwise
            things get cleaned up after a long time */
            gc();
        }

        function onInitFailed(macAddress) {
            root.finishWirelessConnectionAttempt(macAddress)
        }

        function onNoPairingFile(macAddress) {
            root.finishWirelessConnectionAttempt(macAddress)
            root.noPairingFileForWirelessDevice(macAddress)
        }
    }

}
