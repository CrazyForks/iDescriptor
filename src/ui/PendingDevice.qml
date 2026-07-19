import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./base"
import "." as App

Item {
    id: root

    required property string udid

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 28
        anchors.bottomMargin: 28
        spacing: 12

        Item { Layout.fillHeight: true }

        Label {
            Layout.fillWidth: true
            Layout.maximumWidth: 560
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Trust This Computer")
            color: App.Theme.text
            font.pixelSize: 26
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Label {
            Layout.fillWidth: true
            Layout.maximumWidth: 520
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Unlock your device and tap Trust when the prompt appears.")
            color: App.Theme.textMuted
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Image {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumWidth: 560
            Layout.minimumHeight: 210
            Layout.maximumHeight: 360
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8

            source: "qrc:/resources/trust.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: waitingRow.implicitWidth + 24
            implicitHeight: 38
            radius: 19
            color: App.Theme.groupedBackground
            border.color: App.Theme.separator
            border.width: 1

            RowLayout {
                id: waitingRow
                anchors.centerIn: parent
                spacing: 8

                Spinner {
                    Layout.preferredWidth: 25
                    Layout.preferredHeight: 25
                    running: true
                }

                Label {
                    text: qsTr("Waiting for confirmation…")
                    color: App.Theme.textMuted
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
