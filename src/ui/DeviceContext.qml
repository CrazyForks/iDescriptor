pragma Singleton
import QtQml
import QtQml.Models
import QtQuick
import iDescriptor

QtObject {
    id: root
    property ListModel devices: ListModel {}
    property string currentDeviceUdid : ""
    // default to info section
    property int currentSection : 0
    property int currentTab: 0
    property bool showWelcomePage : true
    //Record<mac,pairing_file_path>
    property var pairing_files : ({})

    signal device_removed(string udid)
    signal initStarted(string mac)

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

    // FIXME: doesn't include recovery devices
    function getDeviceCount() {
        return devices.count
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

    function tryToConnectToNetworkDevice(
        mac, ip, force_cache, set_as_selection_if_exists
    ){
        console.log("Trying to connect to network device with MAC:", mac, "IP:", ip, `should force cache=${force_cache}`);

        if (force_cache) {
            cachePairedDevices();
        }

        const existingDevice = root.getDeviceByMacAddress(mac);

        //FIXME
        if (existingDevice) {
            return;
            //emit deviceAlreadyExistsMAC(
            //    iDescriptor::Uniq(existingDevice->deviceInfo.wifiMacAddress, true));
            // TODO: add a setting for this
            //if (setSelectionIfExists) {
            //    setCurrentDeviceSelection(DeviceSelection(existingDevice->udid),
            //                            true);
            //}
            //return;
        }

        cachePairedDevices();
        const pairing_file = root.pairing_files[mac];
        console.log(JSON.stringify(root.pairing_files));
        if (!pairing_file) {
            console.log("No pairing file cached for device with MAC:", mac, "Emitting noPairingFileForWirelessDevice event");
            //emit noPairingFileForWirelessDevice(device.macAddress);
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
                gc()
                break
            }
        }
    }



    // workaround to use connections inside a QtObject
    property var _connections : Connections {
        target: core

        function onDevice_event(eventType, udid, info) {
            console.log("Device event:", eventType, udid, JSON.stringify(info))

            switch (eventType) {
                case 1:
                    const service_manager = serviceFactory.create_service_manager(udid, info.ios_version_major)
                    const sb_client = serviceFactory.create_springboard_services_client(udid)
                    const text = `${info.marketing_name} / ${udid.slice(0,10)}...`
                    root.pairing_files[info["WiFiAddress"]] = QmlUtils.get_lockdown_dir() + `/${udid}.plist`;
                    console.log(JSON.stringify(root.pairing_files));
                    devices.append({ udid: udid, info: info , text , service_manager, sb_client })
                    root.showWelcomePage = false
                    root.currentDeviceUdid = udid
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
                    root.showWelcomePage = devices.count === 0
                    root.currentDeviceUdid = ""
                    root.device_removed(udid)
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
    }

}
