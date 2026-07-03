import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Controls.impl
import QtQuick.Dialogs
import "." as App

Item {
    id: root
    anchors.fill: parent

    property var afcClient: null
    required property string udid 
    property bool useAfc2: false

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

    function _openFileOnDevice(name) {
        if (!afcClient) return
        var path = _fullPath(name)

        if (Helpers.is_previewable(name)) {
            const comp = Qt.createComponent("PreviewWindow.qml")
            if (comp.status === Component.Ready) {
                const win = comp.createObject(null, {
                    filePath: path,
                    udid: root.udid,
                    afcClient: root.afcClient
                })
                if (win !== null) {
                    win.show()
                    return
                }
                console.error("createObject failed:", comp.errorString())
            } else if (comp.status === Component.Error) {
                console.error("Component failed to load:", comp.errorString())
            }
            errorMessage = qsTr("Failed to open preview.")
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
    function _multiSelectModifierPressed(modifiers) {
        if (Qt.platform.os === "osx" || Qt.platform.os === "darwin")
            return (modifiers & Qt.MetaModifier) !== 0

        return (modifiers & Qt.ControlModifier) !== 0
    }

    function _toggleSelectedPath(path) {
        var idx = selectedPaths.indexOf(path)
        if (idx === -1) selectedPaths = selectedPaths.concat([path])
        else selectedPaths = selectedPaths.slice(0, idx).concat(selectedPaths.slice(idx + 1))
        _updateActionEnabled()
    }

    function _selectPath(path, isDir, modifiers) {
        // FIXME: dir
        if (isDir) {
            if (!_multiSelectModifierPressed(modifiers)) {
                selectedPaths = []
                _updateActionEnabled()
            }
            return
        }

        if (_multiSelectModifierPressed(modifiers)) {
            _toggleSelectedPath(path)
            return
        }

        selectedPaths = [path]
        _updateActionEnabled()
    }

    function _updateActionEnabled() {
        exportBtn.enabled = selectedPaths.length > 0 
        deleteBtn.enabled = selectedPaths.length > 0
    }

    function _startExport(destinationDir) {
        if (!ioManager || !root.udid || selectedPaths.length === 0)
            return

        const jobId = QmlUtils.generate_uuid()
        App.StatusWindow.addProcess(
            jobId,
            qsTr("Exporting Files"),
            "Export",
            selectedPaths.length,
            destinationDir
        )
        if (afcClient && afcClient.bundle_id)
            ioManager.start_export_with_hause_arrest_afc(root.udid, jobId, selectedPaths, destinationDir, afcClient.bundle_id)
        else if (root.useAfc2)
            ioManager.start_export_with_afc2(root.udid, jobId, selectedPaths, destinationDir)
        else
            ioManager.start_export(root.udid, jobId, selectedPaths, destinationDir)
    }

    function _startImport(localPaths) {
        if (!ioManager || !root.udid || localPaths.length === 0)
            return

        const jobId = QmlUtils.generate_uuid()
        App.StatusWindow.addProcess(
            jobId,
            qsTr("Importing Files"),
            "Import",
            localPaths.length,
            currentPath
        )
        if (afcClient && afcClient.bundle_id)
            ioManager.start_import_with_hause_arrest_afc(root.udid, jobId, localPaths, currentPath, afcClient.bundle_id)
        else if (root.useAfc2)
            ioManager.start_import_with_afc2(root.udid, jobId, localPaths, currentPath)
        else
            ioManager.start_import(root.udid, jobId, localPaths, currentPath)
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

                        ExplorerToolButton {
                            id: backBtn
                            enabled: false
                            iconSource: "qrc:/resources/icons/material-symbols_arrow-left-alt.svg"
                            tooltip: qsTr("Go Back")
                            onClicked: root.goBack()
                        }

                        ExplorerToolButton {
                            id: forwardBtn
                            enabled: false
                            iconSource: "qrc:/resources/icons/material-symbols_arrow-right-alt.svg"
                            tooltip: qsTr("Go Forward")
                            onClicked: root.goForward()
                        }

                        ExplorerToolButton {
                            id: homeBtn
                            iconSource: "qrc:/resources/icons/material-symbols_home.svg"
                            tooltip: qsTr("Go Home")
                            onClicked: root.goHome()
                        }

                        ExplorerToolButton {
                            id: upBtn
                            enabled: false
                            iconSource: "qrc:/resources/icons/material-symbols_arrow-upward-rounded.svg"
                            tooltip: qsTr("Go Up")
                            onClicked: root.goUp()
                        }

                        TextField {
                            id: addressBar
                            Layout.fillWidth: true
                            placeholderText: qsTr("Enter path...")
                            text: root.currentPath
                            selectByMouse: true
                            onAccepted: root.navigateToPath(text, true)
                        }

                        ExplorerToolButton {
                            id: importBtn
                            enabled: !!root.afcClient
                            iconSource: "qrc:/resources/icons/lets-icons_import.svg"
                            tooltip: qsTr("Import")
                            onClicked: importDialog.open()
                        }

                        ExplorerToolButton {
                            id: exportBtn
                            enabled: false
                            iconSource: "qrc:/resources/icons/ph_export.svg"
                            tooltip: qsTr("Export")
                            onClicked: exportDialog.open()
                        }

                        ExplorerToolButton {
                            id: deleteBtn
                            enabled: false
                            iconSource: "qrc:/resources/icons/material-symbols_delete.svg"
                            tooltip: qsTr("Delete")
                            onClicked: confirmDelete.open()
                        }

                        ExplorerToolButton {
                            id: favBtn
                            visible: root.favEnabled
                            enabled: true
                            iconSource: "qrc:/resources/icons/material-symbols_favorite.svg"
                            tooltip: qsTr("Add to Favorites")
                            onClicked: favDialog.open()
                        }

                        ExplorerToolButton {
                            id: enterBtn
                            iconSource: "qrc:/resources/icons/material-symbols_keyboard-return.svg"
                            tooltip: qsTr("Navigate to path")
                            onClicked: root.navigateToPath(addressBar.text, true)
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
                        radius: 6
                        color: row.entrySelected
                               ? App.Theme.selection
                               : (mouseArea.containsMouse ? App.Theme.hover : "transparent")

                        property string entryName: model.name
                        property bool entryIsDir: model.isDir
                        property string entryPath: root._fullPath(entryName)
                        property bool entrySelected: root._isSelected(entryPath)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            IconImage  {
                                source: model.iconSource
                                Layout.preferredHeight: 34
                                Layout.preferredWidth: 34
                                color: row.entrySelected ? App.Theme.iconSelected : App.Theme.icon
                            }

                            Text {
                                Layout.fillWidth: true
                                text: row.entryName
                                elide: Text.ElideRight
                                color: row.entrySelected ? App.Theme.textSelected : palette.text
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
                                    contextMenu._path = row.entryPath
                                    contextMenu.open()
                                    return
                                }
                                // Single click selects one file; platform modifier toggles multi-select.
                                // Directories do not navigate on single-click.
                                root._selectPath(row.entryPath, row.entryIsDir, mouse.modifiers)
                            }
                        }
                    }
                }

                Menu {
                    id: contextMenu
                    property string _name: ""
                    property string _path: ""
                    property bool _isDir: false

                    MenuItem {
                        text: qsTr("Open")
                        enabled: !contextMenu._isDir
                        onTriggered: root._openFileOnDevice(contextMenu._name)
                    }

                    MenuItem {
                        text: qsTr("Open Externally")
                        enabled: !contextMenu._isDir
                        onTriggered: root._openFileOnDevice(contextMenu._name)
                    }

                    MenuItem {
                        text: qsTr("Export")
                        enabled: !contextMenu._isDir
                        onTriggered: {
                            if (!root._isSelected(contextMenu._path))
                                root.selectedPaths = [contextMenu._path]
                            root._updateActionEnabled()
                            exportDialog.open()
                        }
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

    FolderDialog {
        id: exportDialog
        title: qsTr("Choose Export Folder")
        onAccepted: root._startExport(QmlUtils.url_to_path(selectedFolder))
    }

    FileDialog {
        id: importDialog
        title: qsTr("Choose Files to Import")
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            var paths = []
            for (var i = 0; i < selectedFiles.length; i++)
                paths.push(QmlUtils.url_to_path(selectedFiles[i]))
            root._startImport(paths)
        }
    }

    component ExplorerToolButton: ToolButton {
        id: btn

        property url iconSource: ""
        property string tooltip: ""

        padding: 0
        implicitHeight: 36
        implicitWidth: 36

        transform: Scale {
            origin.x: btn.width / 2
            origin.y: btn.height / 2
            xScale: btn.pressed ? 0.88 : 1.0
            yScale: btn.pressed ? 0.88 : 1.0
            Behavior on xScale { NumberAnimation { duration: 80 } }
            Behavior on yScale { NumberAnimation { duration: 80 } }
        }

        background: Rectangle {
            radius: 8
            color: !btn.enabled
                   ? "transparent"
                   : (btn.pressed ? App.Theme.pressed : (btn.hovered ? App.Theme.hover : "transparent"))
            border.color: btn.activeFocus ? App.Theme.focus : "transparent"
            border.width: 1

            Behavior on color { ColorAnimation { duration: App.Theme.fastAnimation } }
        }

        contentItem: IconImage {
            source: btn.iconSource
            color: btn.enabled ? App.Theme.icon : App.Theme.textMuted
            opacity: btn.enabled ? 1.0 : 0.55
            sourceSize.width: 20
            sourceSize.height: 20
        }

        ToolTip.visible: hovered && tooltip.length > 0
        ToolTip.text: tooltip
    }
}
