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
    //Record<mac,pairing_file_path>
    property var pairing_files : ({})

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
        for (let i = 0; i < devices.count; i++) {
            const device = devices.get(i)
            if (device.info["WiFiAddress"] === mac) {
                return device
            }
        }
        return null
    }

    function cachePairedDevices() {
        Object.assign(root.pairing_files, core.get_pairing_files());
    }

    // receives path of pairing file
    function tryToConnectToNetworkDeviceCustom(ip, path) {
        console.log("QML: Trying to connect to network device with IP:", ip, "and pairing file path:", path);
        core.init_wireless_device_custom(ip, path)
    }

    function tryToConnectToNetworkDevice(
        mac, ip, force_cache, set_as_selection_if_exists
    ){
        console.log("QML: Trying to connect to network device with MAC:", mac, "IP:", ip, `should force cache=${force_cache}`);

        if (force_cache) {
            cachePairedDevices();
        }

        const existingDevice = root.getDeviceByMacAddress(mac);

        //FIXME
        if (existingDevice) {
            console.log("Device with MAC:", mac, "already exists. Emitting deviceAlreadyExistsMAC event");
            root.deviceAlreadyExistsMAC(mac);
            if (set_as_selection_if_exists) {
                console.log("Setting existing device as current selection");
                root.selectConnectedDevice(existingDevice.udid);
            }
            return;
        }

        cachePairedDevices();
        const pairing_file = root.pairing_files[mac];
        console.log(JSON.stringify(root.pairing_files));
        if (!pairing_file) {
            console.log("No pairing file found for MAC:", mac);
            root.noPairingFileForWirelessDevice(mac);
            return;
        }
        //--- fn init_wireless_device(ip: QString, pairing_file: QString, mac_address: QString) ---
        core.init_wireless_device(ip, pairing_file, mac);
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
                case 1:
                    root.removePendingDevice(udid, false)
                    const service_manager = serviceFactory.create_service_manager(udid, info.ios_version_major)
                    const sb_client = serviceFactory.create_springboard_services_client(udid)
                    const text = `${info.marketing_name} / ${udid.slice(0,10)}...`
                    const mac = info["WiFiAddress"]
                    root.pairing_files[mac] = QmlUtils.get_lockdown_dir() + `/${udid}.plist`;
                    console.log(JSON.stringify(root.pairing_files));
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
                    root.selectConnectedDevice(udid)
                    break;
                case 2:
                    // FIXME: find an O(1) solution
                    for (let i = 0; i < devices.count; i++) {
                        const device = devices.get(i)
                        if (device.udid === udid) {
                            devices.remove(i)
                            break
                        }
                    }
                    if (root.currentDeviceUdid === udid)
                        root.currentDeviceUdid = ""
                    root.removePendingDevice(udid, false)
                    root.deviceRemoved(udid)
                    root.selectFallbackDevice()
                    break;
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
        }
    }

}
