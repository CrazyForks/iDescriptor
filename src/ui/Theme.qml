pragma Singleton

import QtQuick

QtObject {
    id: theme

    readonly property SystemPalette _sysPalette: SystemPalette {
        colorGroup: SystemPalette.Active
    }

    readonly property bool darkMode: {
        if (Qt.application.styleHints.colorScheme !== Qt.ColorScheme.Unknown)
            return Qt.application.styleHints.colorScheme === Qt.ColorScheme.Dark;
        return _sysPalette.windowText.hslLightness > _sysPalette.window.hslLightness;
    }

    readonly property color accent: "#0a84ff"
    readonly property color accentPressed: "#006edb"
    readonly property color accentHover: "#006edb"
    readonly property color systemBlue: "#0a84ff"
    readonly property color systemGreen: darkMode ? "#30d158" : "#34c759"
    readonly property color systemOrange: darkMode ? "#ff9f0a" : "#ff9500"
    readonly property color systemRed: darkMode ? "#ff453a" : "#ff3b30"
    readonly property color text: darkMode ? "#f5f5f7" : "#1d1d1f"
    readonly property color textMuted: darkMode ? "#a1a1a6" : "#6e6e73"
    readonly property color textSelected: "#ffffff"
    readonly property color dangerText: darkMode ? "#ff6961" : "#d70015"
    readonly property color icon: darkMode ? "#d1d1d6" : "#3a3a3c"
    readonly property color iconSelected: "#ffffff"
    readonly property color selection: accent
    readonly property color hover: darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.055)
    readonly property color pressed: darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.085)
    readonly property color focus: Qt.rgba(10 / 255, 132 / 255, 255 / 255, darkMode ? 0.55 : 0.42)
    readonly property color controlFill: darkMode ? "#2c2c2e" : "#ffffff"
    readonly property color controlStroke: darkMode ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.1)
    readonly property color softBg: darkMode ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.04)
    readonly property color acrylicSurface: darkMode ? Qt.rgba(31 / 255, 31 / 255, 34 / 255, 0.72) : Qt.rgba(1, 1, 1, 0.72)
    readonly property color acrylicTabTextActive: Qt.rgba(1, 1, 1, 1)
    readonly property color acrylicTabTextInactive: Qt.rgba(1, 1, 1, 0.72)
    readonly property color softBgBorder: darkMode ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.15)
    readonly property color windowBackground: darkMode ? "#1f1f22" : "#f5f5f7"
    readonly property color groupedBackground: darkMode ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.74)
    readonly property color elevatedSurface: darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.88)
    readonly property color rowSurface: darkMode ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(1, 1, 1, 0.62)
    readonly property color separator: darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color selectionSoft: Qt.rgba(10 / 255, 132 / 255, 255 / 255, darkMode ? 0.22 : 0.16)
    readonly property color selectionHover: Qt.rgba(10 / 255, 132 / 255, 255 / 255, darkMode ? 0.14 : 0.10)
    readonly property color selectionStroke: Qt.rgba(10 / 255, 132 / 255, 255 / 255, darkMode ? 0.34 : 0.28)

    readonly property color sidebarBackground: darkMode ? "#1c1c1e" : "#f5f5f7"
    readonly property color sidebarDivider: darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)

    readonly property int sidebarCornerRadius: 8
    readonly property int sidebarRowHeight: 36
    readonly property int sidebarHorizontalPadding: 12
    readonly property int sidebarIconSize: 18
    readonly property int fastAnimation: 160
    readonly property int mediumAnimation: 220
}
