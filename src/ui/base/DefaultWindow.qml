import QtQuick
import QtQuick.Controls

Window {
    id: window
    /* these are required because FluWindow has them but DefaultWindow doesn't */
    property string _effect: "____"
    property bool showMaximize: false
    property bool showMinimize: false
    property bool showClose: false
    property bool auto_close: true
    property bool autoDestroy: true
    property bool autoVisible: false
    property bool fitsAppBarWindows: true  
    property bool setupMacOSWindowStyle: false


    Component.onCompleted : {
        if (Qt.platform.os === "osx" && window.setupMacOSWindowStyle) {
            console.log("Setting up macOS window on update")
            QmlUtils.setup_tool_window(window)
        }
    }
}
