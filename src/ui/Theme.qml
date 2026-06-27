pragma Singleton

import QtQuick

QtObject {
    id: theme

    readonly property bool darkMode: Qt.application.styleHints.colorScheme === Qt.Dark

    readonly property color accent: "#0a84ff"
    readonly property color accentPressed: "#006edb"
    readonly property color sidebarBackground: darkMode ? "#1c1c1e" : "#f5f5f7"
    readonly property color sidebarText: darkMode ? "#f5f5f7" : "#1d1d1f"
    readonly property color sidebarTextMuted: darkMode ? "#a1a1a6" : "#6e6e73"
    readonly property color sidebarIcon: darkMode ? "#d1d1d6" : "#3a3a3c"
    readonly property color sidebarIconSelected: "#ffffff"
    readonly property color sidebarTextSelected: "#ffffff"
    readonly property color sidebarSelection: accent
    readonly property color sidebarHover: darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.055)
    readonly property color sidebarPressed: darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.085)
    readonly property color sidebarFocus: Qt.rgba(10 / 255, 132 / 255, 255 / 255, darkMode ? 0.55 : 0.42)
    readonly property color sidebarDivider: darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color controlFill: darkMode ? "#2c2c2e" : "#ffffff"
    readonly property color controlStroke: darkMode ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.1)

    readonly property int sidebarCornerRadius: 8
    readonly property int sidebarRowHeight: 36
    readonly property int sidebarHorizontalPadding: 12
    readonly property int sidebarIconSize: 18
    readonly property int fastAnimation: 160
    readonly property int mediumAnimation: 220
}
