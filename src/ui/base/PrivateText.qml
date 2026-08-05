// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"

Item {
    id: root

    property string text: ""
    property bool hidden: true
    property int elide: Text.ElideMiddle
    property color color: Theme.text
    property string maskCharacter: "*"
    property int visiblePrefixLength: 4
    property int horizontalPadding: 6
    property int verticalPadding: 2
    property int fontPixelSize: 14
    property bool showingCopied: false
    property int copyFeedbackGeneration: 0
    readonly property bool hasPrivateValue: text !== "" && text !== qsTr("Unknown")
    readonly property string maskedText: maskValue(text)
    readonly property int reservedTextWidth: Math.ceil(Math.max(visibleMetrics.width, hiddenMetrics.width))


    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 4

        Item {
            id: labelFrame
            Layout.fillWidth: true
            implicitWidth: root.reservedTextWidth + (root.horizontalPadding * 2)
            implicitHeight: valueLabel.implicitHeight + (root.verticalPadding * 2)

            Rectangle {
                anchors.fill: parent
                color: copyArea.containsMouse && root.hasPrivateValue ? Theme.softBg : "transparent"
                border.color: copyArea.containsMouse && root.hasPrivateValue ? Theme.softBgBorder : "transparent"
                border.width: 1
                radius: 5

                Behavior on color { ColorAnimation { duration: Theme.fastAnimation } }
            }

            Label {
                id: valueLabel
                anchors.fill: parent
                anchors.leftMargin: root.horizontalPadding
                anchors.rightMargin: root.horizontalPadding
                anchors.topMargin: root.verticalPadding
                anchors.bottomMargin: root.verticalPadding
                text: root.showingCopied
                      ? qsTr("Copied!")
                      : root.hidden && root.hasPrivateValue
                        ? root.maskedText
                        : root.text
                color: root.color
                elide: root.elide
                clip: true
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: root.fontPixelSize
            }

            MouseArea {
                id: copyArea
                anchors.fill: parent
                enabled: root.hasPrivateValue
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: {
                    QmlUtils.copy_to_clipboard(root.text)
                    root.showingCopied = true
                    const generation = ++root.copyFeedbackGeneration
                    Helpers.setTimeout(() => {
                        // prevent multiple clicks from causing the "Copied!" message to disappear too early
                        if (root.copyFeedbackGeneration === generation)
                            root.showingCopied = false
                    }, 1000)
                }
            }
        }

        IconToolButton {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            icon.color: palette.text
            icon.source: !root.hidden
                         ? "qrc:/resources/icons/clarity_eye-line.svg"
                         : "qrc:/resources/icons/clarity_eye-hide-line.svg"
            iconSize: 16

            onClicked: root.hidden = !root.hidden
        }
    }

    TextMetrics {
        id: visibleMetrics
        font: valueLabel.font
        text: root.text
    }

    TextMetrics {
        id: hiddenMetrics
        font: valueLabel.font
        text: root.maskedText
    }

    function maskValue(value) {
        if (!root.hasPrivateValue)
            return value

        const prefixLength = Math.min(root.visiblePrefixLength, Math.max(0, value.length - 1))
        const suffixLength = Math.max(1, value.length - prefixLength)
        return value.slice(0, prefixLength) + root.maskCharacter.repeat(suffixLength)
    }
}
