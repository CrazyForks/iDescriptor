import QtQuick
import QtQuick.Controls
import "."

ApplicationWindow {
    id: window
    title: qsTr("iDescriptor")
    width: 1000
    height: 668
    minimumWidth: 900
    minimumHeight: 550
    visible: true

    Component.onCompleted: {
        Updater.checkAutomatically();
    }

    onClosing: function (close) {
        ClosingHandler.handler("*", close, window);
    }

    MainWorkspace {
        anchors.fill: parent
    }
}
