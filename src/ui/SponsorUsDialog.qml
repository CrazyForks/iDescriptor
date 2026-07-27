import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "./base"
import "." as App

AnimatedDialog {
    id: dialog

    modal: true
    focus: true
    standardButtons: Dialog.NoButton
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    width: 460
    height: 420

    function openSponsorUrl(url) {
        Qt.openUrlExternally(url)
        dialog.close()
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 14

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            radius: width / 2
            color: Qt.rgba(1, 55 / 255, 95 / 255, App.Theme.darkMode ? 0.2 : 0.12)

            Image {
                id: heartIcon
                anchors.centerIn: parent
                width: 32
                height: 32
                source: "qrc:/resources/icons/material-symbols_favorite.svg"
                sourceSize: Qt.size(width, height)
                visible: false
            }

            ColorOverlay {
                anchors.fill: heartIcon
                source: heartIcon
                color: "#ff375f"
            }
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Sponsor iDescriptor")
            color: App.Theme.text
            font.pixelSize: 22
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Your support helps fund ongoing development, testing, and the features the community cares about most.")
            color: App.Theme.textMuted
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        Item { Layout.preferredHeight: 2 }

        Button {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            text: qsTr("Sponsor with GitHub")
            icon.source: "qrc:/resources/icons/mdi_github.svg"
            icon.color: App.Theme.textSelected
            font.bold: true
            highlighted: true
            onClicked: dialog.openSponsorUrl(App.Constants.githubSponsorsUrl)
        }

        Button {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            text: qsTr("Support on Open Collective")
            icon.source: "qrc:/resources/icons/simple-icons_opencollective.svg"
            icon.color: App.Theme.text
            font.bold: true
            onClicked: dialog.openSponsorUrl(App.Constants.openCollectiveUrl)
        }

        Item { Layout.fillHeight: true }

        Button {
            Layout.alignment: Qt.AlignHCenter
            flat: true
            text: qsTr("Maybe later")
            onClicked: dialog.close()
        }
    }
}
