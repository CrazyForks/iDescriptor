import QtQuick 2.15
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: btn
    property bool active: false

    contentItem : Text {
        text : btn.text
        color : btn.active ? "#185ee0" : "#888888"
        font.pixelSize: 22
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Layout.fillWidth: true
    Layout.preferredWidth : 0
    // Layout.fillHeight: true
    background: Rectangle {
        color : "transparent"
    }
}
