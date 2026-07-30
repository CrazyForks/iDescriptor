import QtQuick
import QtQuick.Controls
import FluentUI
import QtQuick.Layouts
import "../../"

FluWindow {
    id: window
    title: qsTr("iDescriptor")
    width: 1000
    height: 668
    minimumWidth: 900
    minimumHeight: 600
    launchMode: FluWindowType.SingleTask
    fitsAppBarWindows: true

    function applyEffect(effect) {
        if (effect === "acrylic") {
            window.backgroundColor = "transparent";
            window.effect = "acrylic";
        } else {
            window.backgroundColor = FluTheme.windowBackgroundColor;
            window.effect = "normal";
        }
    }

    Connections {
        target: Theme
        function onWindowEffectChanged() {
            window.applyEffect(Theme.windowEffect)
        }
    }

    Component.onCompleted: {
        window.applyEffect(settingsManager.window_effect());
        if (!settingsManager.is_window_effect_choice_presented())
            Qt.callLater(() => windowEffectPanel.present());
    }

    WindowEffectPanel {
        id: windowEffectPanel
    }

    onClosing: function (close) {
        ClosingHandler.handler("*", close, window);
    }

    appBar: FluAppBar {
        height: 28
        showDark: false
        showStayTop: false
        z: 7
    }

    MainWorkspace {
        anchors.fill: parent
        // anchors.topMargin: appBar.height
    }
}
