import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../base"
import "../.." as App

AnimatedDialog {
    id: root

    required property var targetWindow
    property string selectedEffect: "normal"

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    anchors.centerIn: parent
    width: 680
    height: 520
    title: qsTr("Choose your desktop appearance")

    onOpened: selectedEffect = settingsManager.window_effect()
    onClosed: settingsManager.set_is_window_effect_choice_presented(true)

    function selectEffect(effect) {
        selectedEffect = effect
        App.Settings.window_effect = effect
        settingsManager.set_window_effect(effect)
        targetWindow.applyEffect(effect)
    }

    contentItem: ColumnLayout {
        spacing: 18

        Label {
            Layout.fillWidth: true
            text: qsTr("How would you like iDescriptor to look on your desktop?")
            color: App.Theme.text
            font.pixelSize: 18
            font.bold: true
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            Repeater {
                model: [
                    {
                        effect: "acrylic",
                        label: qsTr("Acrylic"),
                        // TODO: Replace this placeholder with the final acrylic desktop preview.
                        image: "qrc:/resources/repo/win-11-mica-dark.png"
                    },
                    {
                        effect: "normal",
                        label: qsTr("Normal"),
                        // TODO: Replace this placeholder with the final normal desktop preview.
                        image: "qrc:/resources/repo/win-11-mica-light.png"
                    }
                ]

                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 10
                    color: root.selectedEffect === modelData.effect
                           ? App.Theme.selectionSoft : App.Theme.rowSurface
                    border.width: root.selectedEffect === modelData.effect ? 2 : 1
                    border.color: root.selectedEffect === modelData.effect
                                  ? App.Theme.selection : App.Theme.softBgBorder

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Image {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            source: modelData.image
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            mipmap: true
                        }

                        Label {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: App.Theme.text
                            horizontalAlignment: Text.AlignHCenter
                            font.bold: true
                        }
                    }

                    TapHandler {
                        onTapped: root.selectEffect(modelData.effect)
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("You can always change this later in Settings.")
            color: App.Theme.textMuted
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    footer: DialogButtonBox {
        Button {
            text: qsTr("OK")
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
        onAccepted: root.accept()
    }
}
