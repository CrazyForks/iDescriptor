pragma Singleton
import QtQml
import QtQml.Models
import QtQuick
import iDescriptor

QtObject {
    id: root
    property ListModel devices: ListModel {}
    property ListModel recoveryDevices: ListModel {}
    property string currentDeviceUdid : ""
    property string currentRecoveryDeviceId : ""
    property int currentTab: 0
    property bool showWelcomePage : true
    //Record<mac,pairing_file_path>
    property var pairing_files : ({})

    signal deviceRemoved(string udid)
    signal deviceAdded(string udid, string mac)
    signal deviceAlreadyExistsMAC(string mac)
    signal initStarted(string mac)
    signal noPairingFileForWirelessDevice(string mac)

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

    function getRecoveryDevice(udid) {
        for (let i = 0; i < recoveryDevices.count; i++) {
            const device = recoveryDevices.get(i)
            if (device.udid === udid) {
                return device
            }
        }
        return null
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
                root.currentDeviceUdid = existingDevice.udid;
                root.showWelcomePage = false;
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
                    const service_manager = serviceFactory.create_service_manager(udid, info.ios_version_major)
                    const sb_client = serviceFactory.create_springboard_services_client(udid)
                    const text = `${info.marketing_name} / ${udid.slice(0,10)}...`
                    const mac = info["WiFiAddress"]
                    root.pairing_files[mac] = QmlUtils.get_lockdown_dir() + `/${udid}.plist`;
                    console.log(JSON.stringify(root.pairing_files));
                    devices.append(
                        { udid: udid, info: info , text , service_manager, sb_client,
                    // default to info section
                    currentSection : 0 })
                    root.deviceAdded(udid, mac)
                    root.showWelcomePage = false
                    root.currentDeviceUdid = udid
                    root.currentRecoveryDeviceId = ""
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
                    root.showWelcomePage = root.getDeviceCount() === 0
                    if (root.currentDeviceUdid === udid)
                        root.currentDeviceUdid = ""
                    root.deviceRemoved(udid)
                    break;
                case 3:
                    break;
                case 4:
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
                    if (!root.currentDeviceUdid && !root.currentRecoveryDeviceId)
                        root.currentRecoveryDeviceId = id
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
                    root.showWelcomePage = root.getDeviceCount() === 0
                    break;
            }
        }
    }

}
