// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import iDescriptor
import "../base"

ToolWindow {
    id: root
    width: 820
    height: 620
    minimumWidth: 720
    minimumHeight: 520
    title: qsTr("SSH Terminal / %1 - iDescriptor").arg(deviceName || hostAddress)
    auto_close: false

    required property string connectionType
    required property string deviceName
    required property string deviceUdid
    required property string hostAddress
    required property int port
    required property string rootPassword

    property string errorText: ""
    property string sessionId: connectionType + ":" + deviceUdid + ":" + hostAddress + ":" + Date.now()
    property string terminalHtml: ""
    property string terminalPlainText: ""
    property string pendingTerminalInput: ""
    property string loadingText: connectionType === "wired"
                                 ? qsTr("Setting up SSH tunnel...")
                                 : qsTr("Connecting to network device...")
    property JailbrokenImp jailbrokenImp: JailbrokenImp {}
    property int cursorRow: 0
    property int cursorCol: 0
    property int maxTerminalLines: 2000
    property var terminalLines: []
    property var currentStyle: ({ fg: "#d1fae5", bg: "", bold: false, inverse: false })
    readonly property var ansiColors: ({
        30: "#111827",
        31: "#ef4444",
        32: "#22c55e",
        33: "#eab308",
        34: "#3b82f6",
        35: "#d946ef",
        36: "#06b6d4",
        37: "#e5e7eb",
        90: "#6b7280",
        91: "#f87171",
        92: "#4ade80",
        93: "#facc15",
        94: "#60a5fa",
        95: "#e879f9",
        96: "#22d3ee",
        97: "#f9fafb"
    })
    readonly property var ansiBgColors: ({
        40: "#111827",
        41: "#7f1d1d",
        42: "#14532d",
        43: "#713f12",
        44: "#1e3a8a",
        45: "#701a75",
        46: "#164e63",
        47: "#e5e7eb",
        100: "#374151",
        101: "#991b1b",
        102: "#166534",
        103: "#854d0e",
        104: "#1d4ed8",
        105: "#a21caf",
        106: "#0e7490",
        107: "#f9fafb"
    })

    function htmlEscape(value) {
        return String(value)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
    }

    function defaultStyle() {
        return { fg: "#d1fae5", bg: "", bold: false, inverse: false }
    }

    function cloneStyle(style) {
        return {
            fg: style.fg,
            bg: style.bg,
            bold: style.bold,
            inverse: style.inverse
        }
    }

    function ensureLine(row) {
        while (terminalLines.length <= row)
            terminalLines.push([])
    }

    function trimTerminalBuffer() {
        if (terminalLines.length <= maxTerminalLines)
            return

        const removeCount = terminalLines.length - maxTerminalLines
        terminalLines.splice(0, removeCount)
        cursorRow = Math.max(0, cursorRow - removeCount)
    }

    function putChar(ch) {
        ensureLine(cursorRow)
        const line = terminalLines[cursorRow]
        while (line.length < cursorCol)
            line.push({ ch: " ", style: defaultStyle() })

        line[cursorCol] = {
            ch: ch,
            style: cloneStyle(currentStyle)
        }
        cursorCol += 1
        trimTerminalBuffer()
    }

    function eraseLine(mode) {
        ensureLine(cursorRow)
        const line = terminalLines[cursorRow]
        if (mode === 1) {
            const end = Math.min(cursorCol + 1, line.length)
            for (let i = 0; i < end; ++i)
                line[i] = { ch: " ", style: defaultStyle() }
            return
        }
        if (mode === 2) {
            terminalLines[cursorRow] = []
            return
        }
        line.splice(cursorCol)
    }

    function eraseDisplay(mode) {
        if (mode === 2 || mode === 3) {
            terminalLines = [[]]
            cursorRow = 0
            cursorCol = 0
            return
        }

        ensureLine(cursorRow)
        terminalLines[cursorRow].splice(cursorCol)
        terminalLines.splice(cursorRow + 1)
    }

    function sgr(params) {
        if (params.length === 0)
            params = [0]

        for (let i = 0; i < params.length; ++i) {
            const code = params[i]
            if (code === 0) {
                currentStyle = defaultStyle()
            } else if (code === 1) {
                currentStyle.bold = true
            } else if (code === 22) {
                currentStyle.bold = false
            } else if (code === 7) {
                currentStyle.inverse = true
            } else if (code === 27) {
                currentStyle.inverse = false
            } else if (code === 39) {
                currentStyle.fg = "#d1fae5"
            } else if (code === 49) {
                currentStyle.bg = ""
            } else if (ansiColors[code]) {
                currentStyle.fg = ansiColors[code]
            } else if (ansiBgColors[code]) {
                currentStyle.bg = ansiBgColors[code]
            } else if ((code === 38 || code === 48) && params[i + 1] === 5 && i + 2 < params.length) {
                const color = xtermColor(params[i + 2])
                if (code === 38)
                    currentStyle.fg = color
                else
                    currentStyle.bg = color
                i += 2
            } else if ((code === 38 || code === 48) && params[i + 1] === 2 && i + 4 < params.length) {
                const color = colorFromRgb(params[i + 2], params[i + 3], params[i + 4])
                if (code === 38)
                    currentStyle.fg = color
                else
                    currentStyle.bg = color
                i += 4
            }
        }
    }

    function xtermColor(index) {
        const base = [
            "#000000", "#800000", "#008000", "#808000",
            "#000080", "#800080", "#008080", "#c0c0c0",
            "#808080", "#ff0000", "#00ff00", "#ffff00",
            "#0000ff", "#ff00ff", "#00ffff", "#ffffff"
        ]

        if (index < 16)
            return base[Math.max(0, index)]

        if (index >= 16 && index <= 231) {
            const n = index - 16
            const r = Math.floor(n / 36)
            const g = Math.floor((n % 36) / 6)
            const b = n % 6
            const channel = function(v) { return v === 0 ? 0 : 55 + v * 40 }
            return colorFromRgb(channel(r), channel(g), channel(b))
        }

        const gray = 8 + (Math.max(232, Math.min(255, index)) - 232) * 10
        return colorFromRgb(gray, gray, gray)
    }

    function colorFromRgb(red, green, blue) {
        const channel = function(value) {
            const text = Math.max(0, Math.min(255, Number(value))).toString(16)
            return text.length === 1 ? "0" + text : text
        }

        return "#" + channel(red) + channel(green) + channel(blue)
    }

    function parseCsi(sequence) {
        const finalChar = sequence.charAt(sequence.length - 1)
        const privateMode = sequence.indexOf("?") !== -1
        const body = sequence.slice(0, -1).replace(/[?>!]/g, "")
        const parts = body.length === 0 ? [] : body.split(";")
        const params = []
        for (let i = 0; i < parts.length; ++i)
            params.push(parts[i].length === 0 ? 0 : Number(parts[i]))

        const value = function(index, fallback) {
            if (index >= params.length || params[index] === 0 || isNaN(params[index]))
                return fallback
            return params[index]
        }

        if (privateMode && (finalChar === "h" || finalChar === "l"))
            return

        if (finalChar === "m") {
            sgr(params)
        } else if (finalChar === "A") {
            cursorRow = Math.max(0, cursorRow - value(0, 1))
        } else if (finalChar === "B") {
            cursorRow += value(0, 1)
            ensureLine(cursorRow)
        } else if (finalChar === "C") {
            cursorCol += value(0, 1)
        } else if (finalChar === "D") {
            cursorCol = Math.max(0, cursorCol - value(0, 1))
        } else if (finalChar === "G") {
            cursorCol = Math.max(0, value(0, 1) - 1)
        } else if (finalChar === "H" || finalChar === "f") {
            cursorRow = Math.max(0, value(0, 1) - 1)
            cursorCol = Math.max(0, value(1, 1) - 1)
            ensureLine(cursorRow)
        } else if (finalChar === "K") {
            eraseLine(value(0, 0))
        } else if (finalChar === "J") {
            eraseDisplay(value(0, 0))
        }
    }

    function appendOutput(text) {
        let i = 0
        const input = pendingTerminalInput + String(text)
        pendingTerminalInput = ""

        while (i < input.length) {
            const ch = input.charAt(i)

            if (ch === "\x1b") {
                if (i + 1 >= input.length) {
                    pendingTerminalInput = input.slice(i)
                    break
                }

                const next = input.charAt(i + 1)
                if (next === "[") {
                    let end = i + 2
                    while (end < input.length && !(/[\x40-\x7e]/.test(input.charAt(end))))
                        end += 1
                    if (end < input.length) {
                        parseCsi(input.slice(i + 2, end + 1))
                        i = end + 1
                        continue
                    }

                    pendingTerminalInput = input.slice(i)
                    break
                } else if (next === "]") {
                    let end = i + 2
                    while (end < input.length
                           && input.charAt(end) !== "\x07"
                           && !(input.charAt(end) === "\x1b" && input.charAt(end + 1) === "\\"))
                        end += 1
                    if (end >= input.length) {
                        pendingTerminalInput = input.slice(i)
                        break
                    }

                    i = input.charAt(end) === "\x1b" ? end + 2 : end + 1
                    continue
                } else {
                    i += 2
                    continue
                }
            } else if (ch === "\r") {
                cursorCol = 0
                i += 1
                continue
            } else if (ch === "\n") {
                cursorRow += 1
                cursorCol = 0
                ensureLine(cursorRow)
                trimTerminalBuffer()
                i += 1
                continue
            } else if (ch === "\b") {
                cursorCol = Math.max(0, cursorCol - 1)
                i += 1
                continue
            } else if (ch >= " " || ch === "\t") {
                if (ch === "\t") {
                    const spaces = 8 - (cursorCol % 8)
                    for (let j = 0; j < spaces; ++j)
                        putChar(" ")
                } else {
                    putChar(ch)
                }
            }

            i += 1
        }

        renderTerminal()
        scrollToBottomTimer.restart()
    }

    function cellStyle(cell) {
        let fg = cell.style.fg
        let bg = cell.style.bg
        if (cell.style.inverse) {
            const oldFg = fg
            fg = bg || "#050607"
            bg = oldFg
        }

        let css = "color:" + fg + ";"
        if (bg.length > 0)
            css += "background-color:" + bg + ";"
        if (cell.style.bold)
            css += "font-weight:700;"
        return css
    }

    function renderTerminal() {
        let html = ""
        let plain = ""

        for (let row = 0; row < terminalLines.length; ++row) {
            const line = terminalLines[row]
            let lastStyle = ""

            for (let col = 0; col < line.length; ++col) {
                const cell = line[col]
                const style = cellStyle(cell)
                if (style !== lastStyle) {
                    if (lastStyle.length > 0)
                        html += "</span>"
                    html += "<span style=\"" + style + "\">"
                    lastStyle = style
                }

                html += cell.ch === " " ? "&nbsp;" : htmlEscape(cell.ch)
                plain += cell.ch
            }

            if (lastStyle.length > 0)
                html += "</span>"
            if (row < terminalLines.length - 1) {
                html += "<br>"
                plain += "\n"
            }
        }

        terminalHtml = html
        terminalPlainText = plain
        terminalView.text = terminalHtml
    }

    function sendCommand(command) {
        const trimmed = command.trim()
        if (trimmed.length === 0)
            return
        if (!jailbrokenImp)
            return

        jailbrokenImp.send_input(sessionId, trimmed + "\n")
    }

    function retry() {
        terminalHtml = ""
        terminalPlainText = ""
        pendingTerminalInput = ""
        terminalLines = [[]]
        cursorRow = 0
        cursorCol = 0
        currentStyle = defaultStyle()
        terminalView.text = ""
        errorText = ""
        stateView.viewState = StateView.State.Loading
        if (!jailbrokenImp)
            return

        jailbrokenImp.connect_ssh(
            sessionId,
            connectionType,
            deviceUdid,
            hostAddress,
            port,
            rootPassword
        )
    }

    function shutdownJailbrokenImp() {
        if (!jailbrokenImp)
            return

        jailbrokenImp.shutdown()
        jailbrokenImp = null
    }

    Component.onCompleted: retry()
    Component.onDestruction: shutdownJailbrokenImp()

    onClosing: shutdownJailbrokenImp()

    Connections {
        target: root.jailbrokenImp

        function onOutput_received(session_id, text) {
            if (session_id === root.sessionId)
                root.appendOutput(text)
        }

        function onConnection_state_changed(session_id, state, message) {
            if (session_id !== root.sessionId)
                return

            if (state === "connected") {
                root.appendOutput(message + "\n")
                stateView.viewState = StateView.State.Content
            } else if (state === "loading") {
                root.loadingText = message
                stateView.viewState = StateView.State.Loading
            } else if (state === "closed") {
                root.appendOutput("\n" + message + "\n")
                commandField.enabled = false
            } else if (state === "error") {
                root.errorText = message
                stateView.viewState = StateView.State.Error
            }
        }
    }

    Timer {
        id: scrollToBottomTimer
        interval: 0
        repeat: false
        onTriggered: terminalScroll.ScrollBar.vertical.position = 1.0 - terminalScroll.ScrollBar.vertical.size
    }

    StateView {
        id: stateView
        anchors.fill: parent
        autoSwitchContent: false
        viewState: StateView.State.Loading
        errorText: root.errorText
        retryable: true
        onRetryRequested: root.retry()

        contentItem: Rectangle {
            anchors.fill: parent
            color: "#050607"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                ScrollView {
                    id: terminalScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    TextEdit {
                        id: terminalView
                        width: terminalScroll.availableWidth
                        readOnly: true
                        selectByMouse: true
                        textFormat: TextEdit.RichText
                        color: "#d1fae5"
                        selectedTextColor: "#050607"
                        selectionColor: "#34d399"
                        font.family: "monospace"
                        font.pixelSize: 13
                        wrapMode: TextEdit.NoWrap
                        persistentSelection: true

                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: terminalMenu.popup()
                        }

                        Menu {
                            id: terminalMenu

                            MenuItem {
                                text: qsTr("Copy")
                                enabled: terminalView.selectedText.length > 0
                                onTriggered: terminalView.copy()
                            }

                            MenuItem {
                                text: qsTr("Copy All")
                                enabled: root.terminalPlainText.length > 0
                                onTriggered: {
                                    terminalView.selectAll()
                                    terminalView.copy()
                                    terminalView.deselect()
                                }
                            }

                            MenuSeparator {}

                            MenuItem {
                                text: qsTr("Clear")
                                enabled: root.terminalPlainText.length > 0
                                onTriggered: {
                                    root.terminalHtml = ""
                                    root.terminalPlainText = ""
                                    root.pendingTerminalInput = ""
                                    root.terminalLines = [[]]
                                    root.cursorRow = 0
                                    root.cursorCol = 0
                                    terminalView.text = ""
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: "root#"
                        color: "#7dd3fc"
                        font.family: "monospace"
                        font.pixelSize: 13
                    }

                    TextField {
                        id: commandField
                        Layout.fillWidth: true
                        focus: true
                        color: "#d1fae5"
                        font.family: "monospace"
                        font.pixelSize: 13
                        background: Rectangle {
                            color: "transparent"
                        }
                        onAccepted: {
                            root.sendCommand(text)
                            text = ""
                        }
                    }

                    Button {
                        text: qsTr("Send")
                        enabled: commandField.enabled
                        onClicked: {
                            root.sendCommand(commandField.text)
                            commandField.text = ""
                            commandField.forceActiveFocus()
                        }
                    }

                    Button {
                        text: qsTr("Ctrl-C")
                        enabled: commandField.enabled
                        onClicked: {
                            if (root.jailbrokenImp)
                                root.jailbrokenImp.send_input(root.sessionId, "\x03")
                        }
                    }
                }
            }
        }
    }
}
