import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import ".." as App
import FluentUI

FluWindow {
    id: root
    property bool auto_close: true
    property string _effect: "acrylic"
    launchMode: FluWindowType.Standard 
    backgroundColor: "transparent"
    Component.onCompleted : {
        // directly setting the effect property doesn't work
        root.effect = root._effect
    }
}