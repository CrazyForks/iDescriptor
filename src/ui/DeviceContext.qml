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

    signal device_removed(string udid)

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