import QtQuick
import QtQuick.Controls
import "../"

Item {
    id: root

    property string text: ""
    property int elide: Text.ElideNone
    property int wrapMode: Text.NoWrap
    property color color: Theme.text
    property color backgroundColor: "transparent"
    property real backgroundRadius: 5
    property int horizontalPadding: 0
    property int verticalPadding: 0
    property alias font: valueLabel.font
    readonly property bool canCopy: text.length > 0 && text !== qsTr("Unknown")
    property bool showingCopied: false

    implicitWidth: valueLabel.implicitWidth + (horizontalPadding * 2)
    implicitHeight: valueLabel.implicitHeight + (verticalPadding * 2)

    Rectangle {
        anchors.fill: parent
        color: copyArea.containsMouse && root.canCopy ? Theme.softBg : root.backgroundColor
        border.color: copyArea.containsMouse && root.canCopy ? Theme.softBgBorder : "transparent"
        border.width: 1
        radius: root.backgroundRadius

        Behavior on color { ColorAnimation { duration: Theme.fastAnimation } }
    }

    Label {
        id: valueLabel
        anchors.fill: parent
        anchors.leftMargin: root.horizontalPadding
        anchors.rightMargin: root.horizontalPadding
        anchors.topMargin: root.verticalPadding
        anchors.bottomMargin: root.verticalPadding
        text: root.showingCopied ? qsTr("Copied!") : root.text
        color: root.color
        elide: root.elide
        wrapMode: root.wrapMode
        clip: true
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        id: copyArea
        anchors.fill: parent
        enabled: root.canCopy
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            QmlUtils.copy_to_clipboard(root.text)
            root.showingCopied = true
            copiedTimer.restart()
        }
    }

    Timer {
        id: copiedTimer
        interval: 1000
        onTriggered: root.showingCopied = false
    }
}
