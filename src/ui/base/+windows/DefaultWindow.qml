import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".." as App
import FluentUI

FluWindow {
    id: root
    launchMode: FluWindowType.Standard
    property bool is_complete: false
    property string _effect: ""
    property bool setupMacOSWindowStyle: false


    function applyEffect(effect) {
        if (!root.is_complete) {
            console.warn("Window is not complete yet. Cannot apply effect.")
            return
        }

        if (effect === "acrylic") {
            root.backgroundColor = "transparent"
            root.effect = "acrylic"
        } else {
            root.backgroundColor = FluTheme.windowBackgroundColor
            root.effect = "normal"
        }
    }

    Component.onCompleted : {
        root.is_complete = true
        const effect = root._effect.length > 0 ? root._effect : settingsManager.window_effect()
        root.applyEffect(effect)
    }
}
