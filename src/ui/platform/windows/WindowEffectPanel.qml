// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import "../.." as App

FluFrame {
    id: root

    property string selectedEffect: "normal"

    visible: false
    z: 20
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? parent.height - height - 20 : 0
    width: 500
    height: 350
    radius: 8
    color: App.Theme.darkMode ? Qt.rgba(32 / 255, 32 / 255, 32 / 255, 0.96)
                              : Qt.rgba(249 / 255, 249 / 255, 249 / 255, 0.96)
    border.width: 1
    border.color: App.Theme.softBgBorder

    function present() {
        selectedEffect = settingsManager.window_effect()
        visible = true
    }

    function selectEffect(effect) {
        selectedEffect = effect
        App.Settings.window_effect = effect
        settingsManager.set_window_effect(effect)
        App.Theme.windowEffect = effect
    }

    function acceptChoice() {
        settingsManager.set_is_window_effect_choice_presented(true)
        visible = false
    }

    FluShadow {
        color: App.Theme.darkMode ? "#000000" : "#707070"
        elevation: 8
        radius: root.radius
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        FluText {
            Layout.fillWidth: true
            text: qsTr("Personalize iDescriptor")
            color: App.Theme.text
            font.pixelSize: 20
            font.weight: Font.DemiBold
        }

        FluText {
            Layout.fillWidth: true
            text: qsTr("Choose a window material. Your selection is applied immediately so you can preview it.")
            color: App.Theme.textMuted
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            Repeater {
                model: [
                    {
                        effect: "acrylic",
                        label: qsTr("Acrylic"),
                        description: qsTr("Translucent and layered")
                    },
                    {
                        effect: "normal",
                        label: qsTr("Normal"),
                        description: qsTr("Solid window background")
                    }
                ]

                delegate: Rectangle {
                    id: effectCard

                    required property var modelData
                    readonly property bool selected: root.selectedEffect === modelData.effect
                    readonly property bool hovered: cardHover.hovered

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: selected ? App.Theme.selectionSoft
                                    : hovered ? App.Theme.hover : App.Theme.rowSurface
                    border.width: selected ? 2 : 1
                    border.color: selected ? App.Theme.selection : App.Theme.softBgBorder

                    Behavior on color {
                        ColorAnimation { duration: App.Theme.fastAnimation }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 112
                            clip: true

                            Rectangle {
                                visible: effectCard.modelData.effect === "acrylic"
                                width: 110
                                height: 110
                                radius: 55
                                x: 8
                                y: -28
                                color: Qt.rgba(0.15, 0.50, 0.95, 0.70)
                            }

                            Rectangle {
                                visible: effectCard.modelData.effect === "acrylic"
                                width: 100
                                height: 100
                                radius: 50
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: -26
                                color: Qt.rgba(0.55, 0.25, 0.92, 0.58)
                            }

                            Rectangle {
                                id: previewWindow
                                anchors.fill: parent
                                anchors.margins: 8
                                radius: 7
                                color: effectCard.modelData.effect === "acrylic"
                                       ? (App.Theme.darkMode
                                          ? Qt.rgba(25 / 255, 25 / 255, 28 / 255, 0.72)
                                          : Qt.rgba(1, 1, 1, 0.66))
                                       : App.Theme.windowBackground
                                border.width: 1
                                border.color: App.Theme.controlStroke

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    height: 25
                                    radius: previewWindow.radius
                                    color: effectCard.modelData.effect === "acrylic"
                                           ? Qt.rgba(1, 1, 1, App.Theme.darkMode ? 0.08 : 0.30)
                                           : App.Theme.groupedBackground

                                    Row {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 7

                                        Repeater {
                                            model: 3

                                            Rectangle {
                                                width: 7
                                                height: 7
                                                radius: 2
                                                color: App.Theme.textMuted
                                                opacity: 0.55
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 7
                                    anchors.topMargin: 32
                                    anchors.bottomMargin: 7
                                    width: 38
                                    radius: 4
                                    color: App.Theme.sidebarBackground
                                    opacity: effectCard.modelData.effect === "acrylic" ? 0.76 : 1
                                }

                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 54
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.top: parent.top
                                    anchors.topMargin: 36
                                    spacing: 7

                                    Repeater {
                                        model: [1, 0.72, 0.88]

                                        Rectangle {
                                            required property real modelData
                                            width: parent.width * modelData
                                            height: 8
                                            radius: 4
                                            color: App.Theme.textMuted
                                            opacity: 0.22
                                        }
                                    }
                                }
                            }
                        }

                        FluRadioButton {
                            Layout.fillWidth: true
                            text: effectCard.modelData.label
                            checked: effectCard.selected
                            clickListener: function() {
                                root.selectEffect(effectCard.modelData.effect)
                            }
                        }

                        FluText {
                            Layout.fillWidth: true
                            text: effectCard.modelData.description
                            color: App.Theme.textMuted
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    HoverHandler {
                        id: cardHover
                    }

                    TapHandler {
                        onTapped: root.selectEffect(effectCard.modelData.effect)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            FluText {
                Layout.fillWidth: true
                text: qsTr("You can change this later in Settings.")
                color: App.Theme.textMuted
                font.pixelSize: 12
            }

            FluFilledButton {
                Layout.preferredWidth: 88
                text: qsTr("OK")
                onClicked: root.acceptChoice()
            }
        }
    }
}
