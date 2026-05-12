pragma Singleton
import QtQml 2.15
import QtQml.Models 2.15
import QtQuick 2.15
import iDescriptor 1.0

/* 
    core is a global obj set from rust side
    engine.set_object_property("core".into(), core_obj.pinned());
*/
QtObject {
    id: root
    property ListModel devices: ListModel {}
    property string currentDeviceUdid : ""
    // default to info section
    property int currentSection : 0 

    property bool showWelcomePage : true

    function init() {
        core.init()

    }

    // workaround to use connections inside a QtObject
    property var _connections : Connections {
        target: core

        function onDevice_event(eventType, udid, info) {
            console.log("Device event:", eventType, udid, JSON.stringify(info))
            
            switch (eventType) {
                case 1:
                    // FIXME: text should be  `$device_market_name / $udid `
                    devices.set(udid, { udid: udid, info: info , text: `TODO` })
                    root.showWelcomePage = false
                    root.currentDeviceUdid = udid
                    break;
                case 2:
                    devices.remove(udid)
                    root.showWelcomePage = !!devices.count
                    root.currentDeviceUdid = ""

                    break;
                case 3:
                    break;
                case 4:
                    break;
                default:

            }
        }
    }

}