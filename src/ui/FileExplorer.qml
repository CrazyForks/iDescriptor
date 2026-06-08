import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls.impl

// FIXME: wire up export logic
Item {
    id: root
    anchors.fill: parent

    property var afcClient: null

    property bool favEnabled: true
    property string rootPath: "/"

    property string currentPath: "/"
    property bool loading: false
    property string errorMessage: ""

    property var backStack: []
    property var forwardStack: []

    function normalizePath(p) {
        var path = (p || "").trim()
        if (path.length === 0) path = "/"
        if (path[0] !== "/") path = "/" + path
        // collapse repeated slashes
        path = path.replace(/\/+/g, "/")
        if (path.length > 1 && path.endsWith("/")) path = path.slice(0, -1)
        return path
    }

    function _setLoading(on) {
        loading = on
        if (on) errorMessage = ""
    }

    function refresh() {
        if (!afcClient) {
            errorMessage = qsTr("AFC client is not available.")
            return
        }
        _setLoading(true)
        afcClient.check_is_dir_and_list(currentPath)
    }

    function navigateToPath(path, pushHistory) {
        var next = normalizePath(path)
        if (pushHistory === undefined) pushHistory = true

        if (pushHistory) {
            if (currentPath !== next) {
                backStack = backStack.concat([currentPath])
                forwardStack = []
            }
        }

        currentPath = next
        addressBar.text = next
        refresh()
        _updateNavEnabled()
    }

    function goHome() { navigateToPath(rootPath, true) }

    function goBack() {
        if (backStack.length === 0) return
        var prev = backStack[backStack.length - 1]
        backStack = backStack.slice(0, -1)
        forwardStack = forwardStack.concat([currentPath])
        navigateToPath(prev, false)
    }

    function goForward() {
        if (forwardStack.length === 0) return
        var next = forwardStack[forwardStack.length - 1]
        forwardStack = forwardStack.slice(0, -1)
        backStack = backStack.concat([currentPath])
        navigateToPath(next, false)
    }

    function goUp() {
        var p = normalizePath(currentPath)
        if (p === "/") return
        var idx = p.lastIndexOf("/")
        var parentPath = (idx <= 0) ? "/" : p.slice(0, idx)
        navigateToPath(parentPath, true)
    }

    function _updateNavEnabled() {
        backBtn.enabled = backStack.length > 0
        forwardBtn.enabled = forwardStack.length > 0
        upBtn.enabled = normalizePath(currentPath) !== "/"
    }

    function _fullPath(name) {
        var base = normalizePath(currentPath)
        if (base === "/") return "/" + name
        return base + "/" + name
    }

    // TODO: maybe call from rust 
    function _isPreviewable(name) {
        var lower = (name || "").toLowerCase()
        return lower.endsWith(".mp4") || lower.endsWith(".m4v") || lower.endsWith(".mov") ||
               lower.endsWith(".avi") || lower.endsWith(".mkv")
    }

    function _openFileOnDevice(name) {
        if (!afcClient) return
        var path = _fullPath(name)

        if (_isPreviewable(name)) {
            var url = afcClient.start_video_stream(path)
            if (url && url.length > 0) {
                Qt.openUrlExternally(url)
                return
            }
            // fallthrough to error
            errorMessage = qsTr("Failed to start stream.")
            return
        }

        errorMessage = qsTr("Open is not implemented for this file type yet.")
    }

    function _deleteSelected() {
        if (!afcClient) return
        if (selectedPaths.length === 0) return

        _setLoading(true)
        var ok = true
        for (var i = 0; i < selectedPaths.length; i++) {
            var p = selectedPaths[i]
            var r = afcClient.delete_path(p)
            if (!r) ok = false
        }

        selectedPaths = []
        if (!ok) {
            _setLoading(false)
            errorMessage = qsTr("Failed to delete one or more items.")
            return
        }
        refresh()
    }

    ListModel { id: entriesModel }

    property var selectedPaths: []
    function _isSelected(path) { return selectedPaths.indexOf(path) !== -1 }
    function _toggleSelected(path, isDir) {
        // FIXME: dir
        if (isDir) return
        var idx = selectedPaths.indexOf(path)
        if (idx === -1) selectedPaths = selectedPaths.concat([path])
        else selectedPaths = selectedPaths.slice(0, idx).concat(selectedPaths.slice(idx + 1))
        _updateActionEnabled()
    }

    function _updateActionEnabled() {
        exportBtn.enabled = selectedPaths.length > 0 
        deleteBtn.enabled = selectedPaths.length > 0
    }

    Connections {
        target: afcClient
        enabled: !!afcClient

        function onCheck_is_dir_and_list_finished(success, entries) {
            entriesModel.clear()

            if (!success) {
                root.loading = false
                root.errorMessage = qsTr("Failed to load directory.")
                return
            }

            // entries is QVariantMap: name -> isDir(bool)
            var names = []
            for (var k in entries) names.push(k)
            names.sort()

            // dirs first, then files (approx)
            var dirs = []
            var files = []
            for (var i = 0; i < names.length; i++) {
                var name = names[i]
                var isDir = !!entries[name]
                var iconSource = isDir
                    ? "qrc:/resources/icons/material-symbols_folder.svg"
                    : "qrc:/resources/icons/ic_baseline-insert-drive-file.svg"
                var item = { "name": name, "isDir": isDir, "iconSource": iconSource }
                if (isDir) dirs.push(item); else files.push(item)
            }

            for (var d = 0; d < dirs.length; d++) entriesModel.append(dirs[d])
            for (var f = 0; f < files.length; f++) entriesModel.append(files[f])

            root.loading = false
            root.errorMessage = ""
            root.selectedPaths = []
            root._updateActionEnabled()
            root._updateNavEnabled()
        }
    }

    onAfcClientChanged: {
        backStack = []
        forwardStack = []
        selectedPaths = []
        currentPath = normalizePath(rootPath)
        addressBar.text = currentPath
        if (afcClient) refresh()
        else errorMessage = qsTr("AFC client is not available.")
        _updateNavEnabled()
        _updateActionEnabled()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 58

            RowLayout {
                anchors.fill: parent

                Item { Layout.fillWidth: true }

                Rectangle {
                    id: navWidget
                    Layout.preferredWidth: 700
                    Layout.preferredHeight: 44
                    radius: 10
                    color: "transparent"
                    border.width: 1
                    border.color: "#22000000"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 6

                        ToolButton {
                            id: backBtn
                            enabled: false
                            onClicked: root.goBack()

                            padding: 0
                            implicitHeight: 44
                            implicitWidth: 44

                            contentItem: Item {
                                anchors.fill: parent
                                Button {
                                    anchors.fill: parent
                                    icon.source: "qrc:/resources/icons/material-symbols_arrow-left-alt.svg"
                                    // FIXME:theming
                                    opacity: backBtn.enabled ? 1.0 : 0.7
                                }
                            }

                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Go Back")
                        }

                        ToolButton {
                            id: forwardBtn
                            enabled: false
                            onClicked: root.goForward()

                            padding: 0
                            implicitHeight: 44
                            implicitWidth: 44

                            contentItem: Item {
                                anchors.fill: parent
                                Button {
                                    anchors.fill: parent
                                    icon.source: "qrc:/resources/icons/material-symbols_arrow-right-alt.svg"
                                    // FIXME:theming
                                    opacity: forwardBtn.enabled ? 1.0 : 0.7
                                }
                            }

                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Go Forward")
                        }

                        ToolButton {
                            id: homeBtn
                            onClicked: root.goHome()

                            padding: 0
                            implicitHeight: 44
                            implicitWidth: 44

                            contentItem: Item {
                                anchors.fill: parent
                                Button {
                                    anchors.fill: parent
                                    icon.source: "qrc:/resources/icons/material-symbols_home.svg"
                                    // FIXME:theming
                                    opacity: homeBtn.enabled ? 1.0 : 0.7
                                }
                            }

                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Go Home")
                        }

                        ToolButton {
                            id: upBtn
                            enabled: false
                            onClicked: root.goUp()

                            padding: 0
                            implicitHeight: 44
                            implicitWidth: 44

                            contentItem: Item {
                                anchors.fill: parent
                                Button {
                                    anchors.fill: parent
                                    icon.source: "qrc:/resources/icons/material-symbols_arrow-upward-rounded.svg"
                                    // FIXME:theming
                                    opacity: upBtn.enabled ? 1.0 : 0.7
                                }
                            }

                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Go Up")
                        }

                        TextField {
                            id: addressBar
                            Layout.fillWidth: true
                            placeholderText: qsTr("Enter path...")
                            text: root.currentPath
                            selectByMouse: true
                            onAccepted: root.navigateToPath(text, true)
                        }

                        ToolButton {
                            id: importBtn
                            enabled: false

                            padding: 0
                            implicitHeight: 44
                            implicitWidth: 44

                            contentItem: Item {
                                anchors.fill: parent
                                Button {
                                    anchors.fill: parent
                                    icon.source: "qrc:/resources/icons/lets-icons:import.svg"
                                    // FIXME:theming
                                    opacity: importBtn.enabled ? 1.0 : 0.7
                                }
                            }

                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Import (FIXME)")
                        }

                        ToolButton {
                            id: exportBtn
                            enabled: false

                            padding: 0
                            implicitHeight: 44
                            implicitWidth: 44

                            contentItem: Item {
                                anchors.fill: parent
                                Button {
                                    anchors.fill: parent
                                    icon.source: "qrc:/resources/icons/ph_export.svg"
                                    // FIXME:theming
                                    opacity: exportBtn.enabled ? 1.0 : 0.7
                                }
                            }

                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Export (FIXME)")
                        }

                        ToolButton {
                            id: deleteBtn
                            enabled: false
                            onClicked: confirmDelete.open()

                            padding: 0
                            implicitHeight: 44
                            implicitWidth: 44

                            contentItem: Item {
                                anchors.fill: parent
                                Button {
                                    anchors.fill: parent
                                    icon.source: "qrc:/resources/icons/material-symbols_delete.svg"
                                    // FIXME:theming
                                    opacity: deleteBtn.enabled ? 1.0 : 0.7
                                }
                            }

                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Delete")
                        }

                        ToolButton {
                            id: favBtn
                            visible: root.favEnabled
                            enabled: true
                            onClicked: favDialog.open()

                            padding: 0
                            implicitHeight: 44
                            implicitWidth: 44

                            contentItem: Item {
                                anchors.fill: parent
                                Button {
                                    anchors.fill: parent
                                    icon.source: "qrc:/resources/icons/material-symbols_favorite.svg"
                                    // FIXME:theming
                                    opacity: favBtn.enabled ? 1.0 : 0.7
                                }
                            }

                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Add to Favorites")
                        }

                        ToolButton {
                            id: enterBtn
                            onClicked: root.navigateToPath(addressBar.text, true)

                            padding: 0
                            implicitHeight: 44
                            implicitWidth: 44

                            contentItem: Item {
                                anchors.fill: parent
                                Button {
                                    anchors.fill: parent
                                    icon.source: "qrc:/resources/icons/material-symbols_keyboard-return.svg"
                                    // FIXME:theming
                                    opacity: enterBtn.enabled ? 1.0 : 0.7
                                }
                            }

                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Navigate to path")
                        }
                    }
                }

                Item { Layout.fillWidth: true } 
            }
        }

        // Content states
        StackLayout {
            id: contentStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.loading ? 1 : (root.errorMessage.length > 0 ? 2 : 0)

            // File list
            Item {
                anchors.fill: parent

                ListView {
                    id: listView
                    anchors.fill: parent
                    clip: true
                    model: entriesModel

                    delegate: Rectangle {
                        id: row
                        width: ListView.view.width
                        height: 44
                        color: (mouseArea.containsMouse ? "#0f000000" : "transparent")

                        property string entryName: model.name
                        property bool entryIsDir: model.isDir
                        property string entryPath: root._fullPath(entryName)
                        property bool entrySelected: root._isSelected(entryPath)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            CheckBox {
                                visible: !row.entryIsDir
                                checked: row.entrySelected
                                onClicked: root._toggleSelected(row.entryPath, row.entryIsDir)
                            }

                            Button {
                                icon.source: model.iconSource
                                Layout.preferredHeight: 34
                                Layout.preferredWidth: 34
                                // FIXME:theming
                                opacity: 1.0
                            }

                            Text {
                                Layout.fillWidth: true
                                text: row.entryName
                                elide: Text.ElideRight
                                color: "#111"
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton

                            onDoubleClicked: {
                                if (row.entryIsDir) {
                                    root.navigateToPath(row.entryPath, true)
                                } else {
                                    root._openFileOnDevice(row.entryName)
                                }
                            }

                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    contextMenu._name = row.entryName
                                    contextMenu._isDir = row.entryIsDir
                                    contextMenu.open()
                                    return
                                }
                                // single click: toggle selection for files, navigate for dirs (QWidget parity: approximate)
                                if (row.entryIsDir) {
                                    // single-click doesn't navigate in the QWidget; keep it inert.
                                    return
                                }
                                root._toggleSelected(row.entryPath, row.entryIsDir)
                            }
                        }
                    }
                }

                Menu {
                    id: contextMenu
                    property string _name: ""
                    property bool _isDir: false

                    MenuItem {
                        text: qsTr("Open")
                        enabled: !contextMenu._isDir
                        onTriggered: root._openFileOnDevice(contextMenu._name)
                    }

                    MenuItem {
                        text: qsTr("Open Externally")
                        enabled: !contextMenu._isDir
                        onTriggered: root._openFileOnDevice(contextMenu._name) // uses stream + Qt.openUrlExternally for previewables
                    }

                    MenuItem {
                        text: qsTr("Export")
                        enabled: false
                    }
                }
            }

            // Loading
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 10
                BusyIndicator { running: true }
                Text { text: qsTr("Loading..."); color: "#444" }
            }

            // Error
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 10
                width: Math.min(parent.width * 0.8, 520)

                Text {
                    text: root.errorMessage
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: "#444"
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Button { text: qsTr("Try Again"); onClicked: root.refresh() }
                }
            }
        }
    }

    Dialog {
        id: favDialog
        modal: true
        title: qsTr("Add to Favorites")
        standardButtons: Dialog.Ok | Dialog.Cancel

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            Text { text: qsTr("Enter alias for this location:") }
            TextField { id: favAlias; placeholderText: qsTr("Alias here") }
            Text { text: qsTr("Path: ") + root.currentPath; color: "#666" }
        }

        onAccepted: {
            var alias = (favAlias.text || "").trim()
            if (alias.length === 0) return
            // FIXME: persist
            // favoritePlaceAdded(alias, root.currentPath)
            favAlias.text = ""
        }
        onRejected: favAlias.text = ""
    }

    Dialog {
        id: confirmDelete
        modal: true
        title: qsTr("Confirm Deletion")
        standardButtons: Dialog.Yes | Dialog.No

        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            Text {
                text: qsTr("Are you sure you want to delete the selected item(s)?")
                wrapMode: Text.WordWrap
            }
            Text { text: qsTr("Count: ") + root.selectedPaths.length; color: "#666" }
        }

        onAccepted: root._deleteSelected()
    }
}
