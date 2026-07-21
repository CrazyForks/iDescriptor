import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import ".." as App

Rectangle {
    id: root
    color: "transparent"
    border.width: 1
    border.color: palette.text
    radius: 10
    signal sponsorshipRequested()


    RowLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 5

            Label {
                Layout.fillWidth: true
                text: qsTr("Sponsor Us!")
                color: App.Theme.text
                font.pixelSize: 16
                font.bold: true
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Support development and feature requests while becoming our first featured sponsor.")
                color: App.Theme.textMuted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        Button {
            id: sponsorButton
            Layout.alignment: Qt.AlignVCenter
            text: qsTr("Sponsor us")
            font.bold: true
            onClicked: root.sponsorshipRequested()

            contentItem: Text {
                text: sponsorButton.text
                color: App.Theme.textSelected
                font: sponsorButton.font
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                radius: 6
                color: sponsorButton.down ? App.Theme.accentPressed
                                          : (sponsorButton.hovered ? App.Theme.accentHover : App.Theme.accent)
            }
        }
    }
}
