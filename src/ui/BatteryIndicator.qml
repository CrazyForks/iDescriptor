// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls

Item {
    id: root

    property real value: 0
    property real maxValue: 100
    property bool isCharging: false
    property color levelColor: "#44bd32"
    property color frameColor: "gray"
    property color textColor: palette.text
    readonly property real normalizedValue: {
        if (root.maxValue <= 0)
            return 0;

        return Math.max(0, Math.min(1, root.value / root.maxValue));
    }
    readonly property int percentValue: Math.round(root.normalizedValue * 100)
    readonly property color effectiveLevelColor: root.isCharging ? "#44bd32" : root.levelColor
    readonly property int batteryWidth: Math.max(28, Math.min(root.width - 4, 52))
    readonly property int batteryHeight: Math.max(14, Math.round(root.batteryWidth * 0.46))

    function setValue(newValue) {
        root.value = newValue;
    }

    function getValue() {
        return root.value;
    }

    function setChargingState(state) {
        root.isCharging = state;
    }

    function updateContext(isCharging, newValue) {
        root.isCharging = isCharging;
        root.value = newValue;
    }

    function getChargingState() {
        return root.isCharging;
    }

    implicitWidth: 40
    implicitHeight: 40
    ToolTip.visible: hoverHandler.hovered
    ToolTip.text: root.isCharging ? qsTr("Charging: %1%").arg(root.percentValue) : qsTr("Battery: %1%").arg(root.percentValue)

    HoverHandler {
        id: hoverHandler
    }

    Item {
        id: battery

        width: root.batteryWidth
        height: root.batteryHeight
        anchors.centerIn: parent

        Rectangle {
            id: body

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - terminal.width + 1
            height: parent.height
            radius: 4
            color: "transparent"
            border.width: 1
            border.color: root.frameColor

            Rectangle {
                id: level

                anchors.left: parent.left
                anchors.leftMargin: 3
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, (parent.width - 6) * root.normalizedValue)
                height: parent.height - 6
                radius: Math.min(3, height / 2)
                color: root.effectiveLevelColor

                Behavior on width {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }

                }

            }

        }

        Rectangle {
            id: terminal

            width: 4
            height: Math.max(6, Math.round(parent.height * 0.45))
            radius: 1
            anchors.left: body.right
            anchors.leftMargin: -1
            anchors.verticalCenter: body.verticalCenter
            color: root.frameColor
        }

        Text {
            anchors.centerIn: body
            text: root.percentValue
            color: root.textColor
            font.pixelSize: Math.max(8, Math.round(body.height * 0.48))
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            visible: body.width >= 30 && !root.isCharging
        }

        Canvas {
            id: chargingIcon

            anchors.centerIn: body
            width: Math.max(10, body.height)
            height: Math.max(12, body.height + 2)
            visible: root.isCharging
            opacity: root.isCharging ? 1 : 0
            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = root.textColor;
                ctx.beginPath();
                ctx.moveTo(width * 0.58, 0);
                ctx.lineTo(width * 0.28, height * 0.52);
                ctx.lineTo(width * 0.52, height * 0.52);
                ctx.lineTo(width * 0.4, height);
                ctx.lineTo(width * 0.74, height * 0.42);
                ctx.lineTo(width * 0.5, height * 0.42);
                ctx.closePath();
                ctx.fill();
            }

            Connections {
                function onTextColorChanged() {
                    chargingIcon.requestPaint();
                }

                target: root
            }

        }

    }

}
