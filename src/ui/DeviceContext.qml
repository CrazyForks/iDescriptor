pragma Singleton
import QtQml 2.15
import QtQml.Models 2.15
import QtQuick 2.15
import iDescriptor 1.0

QtObject {
    id: root
    property ListModel devices: ListModel {}
    property string currentDeviceUdid : ""
    // default info section
    property int currentSection : 0 

    property bool showWelcomePage : true
    readonly property Core core: Core {}

    function init() {
        root.core.init()

    }

    // workaround to use connections inside a QtObject
    property var _connections : Connections {
        target: root.core

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