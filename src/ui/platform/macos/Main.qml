import QtQuick
import QtQuick.Controls
import "../../"

ApplicationWindow {
    id: window
    title: qsTr("iDescriptor")
    width: 1000
    height: 668
    minimumWidth: 900
    minimumHeight: 600
    topPadding: 0
    leftPadding: 0
    rightPadding: 0
    bottomPadding: 0
    visible: true
    flags: Qt.Window | Qt.NoTitleBarBackgroundHint | Qt.ExpandedClientAreaHint

    Component.onCompleted: {
        Qt.callLater(function () {
            QmlUtils.setup_main_window(window.contentItem.Window.window);
        });
        Updater.checkAutomatically();
    }

    onClosing: function (close) {
        ClosingHandler.handler("*", close, window);
    }

    MainWorkspace {
        anchors.fill: parent
    }

    // needed on macos
    // allows us to drag the window
    MouseArea {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 30
        enabled: true
        acceptedButtons: Qt.LeftButton
        z: 1000
        onPressed: function (mouse) {
            window.startSystemMove();
            mouse.accepted = false;
        }
    }
}
