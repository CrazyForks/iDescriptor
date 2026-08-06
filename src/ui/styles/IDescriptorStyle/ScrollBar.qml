// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T

T.ScrollBar {
    id: control

    readonly property bool handleExpanded: control.interactive && (control.hovered || control.pressed)
    readonly property bool handleVisible: control.policy === T.ScrollBar.AlwaysOn || ((control.active || control.hovered || control.pressed) && control.size < 1)

    implicitWidth: orientation === Qt.Vertical ? 10 : 48
    implicitHeight: orientation === Qt.Horizontal ? 10 : 48
    visible: policy !== T.ScrollBar.AlwaysOff
    hoverEnabled: true
    minimumSize: {
        const availableLength = orientation === Qt.Horizontal ? width : height;
        return Math.min(1, 32 / Math.max(availableLength, 32));
    }

    leftPadding: orientation === Qt.Vertical ? (handleExpanded ? 1 : 2.5) : 2
    rightPadding: leftPadding
    topPadding: orientation === Qt.Horizontal ? (handleExpanded ? 1 : 2.5) : 2
    bottomPadding: topPadding

    Behavior on leftPadding {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    Behavior on rightPadding {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    Behavior on topPadding {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    Behavior on bottomPadding {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    contentItem: Rectangle {
        radius: Math.min(width, height) / 2
        color: {
            const source = control.palette.windowText;
            const alpha = control.pressed ? 0.64 : control.hovered ? 0.50 : 0.34;
            return Qt.rgba(source.r, source.g, source.b, alpha);
        }
        opacity: 0

        states: State {
            name: "visible"
            when: control.handleVisible
            PropertyChanges {
                control.contentItem.opacity: 1
            }
        }

        transitions: [
            Transition {
                to: "visible"
                NumberAnimation {
                    property: "opacity"
                    duration: 90
                }
            },
            Transition {
                from: "visible"
                SequentialAnimation {
                    PauseAnimation {
                        duration: 650
                    }
                    NumberAnimation {
                        property: "opacity"
                        duration: 180
                    }
                }
            }
        ]

        Behavior on color {
            ColorAnimation {
                duration: 160
            }
        }
    }
}
