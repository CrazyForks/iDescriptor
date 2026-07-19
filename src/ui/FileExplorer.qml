import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Controls.impl
import QtQuick.Dialogs
import "." as App
import "./base"

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

    signal favoritePlaceAdded(string alias, string path)

    function normalizePath(p) {
        var path = (p || "").trim()
        if (path.length === 0) path = "/"
        if (path[0] !== "/") path = "/" + path
        // collapse repeated slashes
        path = path.replace(/\/+/g, "/")
        if (path.length > 1 && path.endsWith("/")) path = path.slice(0, -1)
        return path
    }

    function setLoading(on) {
        loading = on
        if (on) errorMessage = ""
    }

    function refresh() {
        if (!afcClient) {
            errorMessage = qsTr("AFC client is not available.")
            return
        }
        setLoading(true)
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
        updateNavigationEnabled()
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

    function updateNavigationEnabled() {
        backBtn.enabled = backStack.length > 0
        forwardBtn.enabled = forwardStack.length > 0
        upBtn.enabled = normalizePath(currentPath) !== "/"
    }

    function fullPath(name) {
        var base = normalizePath(currentPath)
        if (base === "/") return "/" + name
        return base + "/" + name
    }

    function openFileOnDevice(name) {
        if (!afcClient) return
        var path = fullPath(name)

        if (Helpers.is_previewable(name)) {
            const comp = Qt.createComponent("PreviewWindow.qml")
            if (comp.status === Component.Ready) {
                console.log("Opening preview for", path)
                console.log("afcClient defined?", !!afcClient)
                console.log("root.udid:", root.udid)
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

    function deleteSelected() {
        if (!afcClient) return
        if (selectedPaths.length === 0) return

        setLoading(true)
        var ok = true
        for (var i = 0; i < selectedPaths.length; i++) {
            var p = selectedPaths[i]
            var r = afcClient.delete_path(p)
            if (!r) ok = false
        }

        selectedPaths = []
        if (!ok) {
            setLoading(false)
            errorMessage = qsTr("Failed to delete one or more items.")
            return
        }
        refresh()
    }

    ListModel { id: entriesModel }

    property var selectedPaths: []

    function isSelected(path) { return selectedPaths.indexOf(path) !== -1 }
    function multiSelectModifierPressed(modifiers) {
        if (Qt.platform.os === "osx" || Qt.platform.os === "darwin")
            return (modifiers & Qt.MetaModifier) !== 0

        return (modifiers & Qt.ControlModifier) !== 0
    }

    function toggleSelectedPath(path) {
        var idx = selectedPaths.indexOf(path)
        if (idx === -1) selectedPaths = selectedPaths.concat([path])
        else selectedPaths = selectedPaths.slice(0, idx).concat(selectedPaths.slice(idx + 1))
        updateActionEnabled()
    }

    function selectPath(path, modifiers) {
        if (multiSelectModifierPressed(modifiers)) {
            toggleSelectedPath(path)
            return
        }

        selectedPaths = [path]
        updateActionEnabled()
    }

    function updateActionEnabled() {
        exportBtn.enabled = selectedPaths.length > 0
        deleteBtn.enabled = selectedPaths.length > 0
    }

    function startExport(destinationDir) {
        if (!ioManager || !root.udid || selectedPaths.length === 0)
            return

        const jobId = QmlUtils.generate_uuid()
        App.StatusWindow.addProcess(
            jobId,
            qsTr("Exporting Files"),
            qsTr("Export"),
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

    function startImport(localPaths) {
        if (!ioManager || !root.udid || localPaths.length === 0)
            return

        const jobId = QmlUtils.generate_uuid()
        App.StatusWindow.addProcess(
            jobId,
            qsTr("Importing Files"),
            qsTr("Import"),
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
            root.updateActionEnabled()
            root.updateNavigationEnabled()
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
        updateNavigationEnabled()
        updateActionEnabled()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0


        SectionBox {
            id: navWidget
            Layout.fillWidth: true
            Layout.preferredHeight: 58
            Layout.margins: 12

            RowLayout {
                anchors.fill: parent
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

                ExplorerToolButton {
                    iconSource: "qrc:/resources/icons/ic_outline-refresh.svg"
                    tooltip: qsTr("Refresh")
                    enabled: !!root.afcClient && !root.loading
                    onClicked: root.refresh()
                }

                TextField {
                    id: addressBar
                    Layout.fillWidth: true
                    Layout.minimumWidth: 100

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


        StateView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            autoSwitchContent: false
            viewState: root.loading
                ? StateView.State.Loading
                : root.errorMessage.length > 0 ? StateView.State.Error : StateView.State.Content
            errorText: root.errorMessage
            onRetryRequested: root.refresh()

            contentItem: Item {
                anchors.fill: parent

                ListView {
                    id: listView
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.bottomMargin: 12
                    clip: true
                    model: entriesModel
                    spacing: 2

                    delegate: Rectangle {
                        id: row
                        width: ListView.view.width
                        height: 44
                        radius: App.Theme.sidebarCornerRadius
                        color: row.entrySelected
                            ? App.Theme.selectionSoft
                            : mouseArea.containsMouse ? App.Theme.hover : "transparent"
                        border.color: row.entrySelected ? App.Theme.selectionStroke : "transparent"
                        border.width: 1

                        property string entryName: model.name
                        property bool entryIsDir: model.isDir
                        property string entryPath: root.fullPath(entryName)
                        property bool entrySelected: root.isSelected(entryPath)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            IconImage {
                                source: model.iconSource
                                sourceSize.width: 22
                                sourceSize.height: 22
                                Layout.preferredHeight: 22
                                Layout.preferredWidth: 22
                                color: row.entrySelected ? App.Theme.systemBlue : App.Theme.icon
                            }

                            Text {
                                Layout.fillWidth: true
                                text: row.entryName
                                elide: Text.ElideRight
                                color: App.Theme.text
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
                                    root.openFileOnDevice(row.entryName)
                                }
                            }

                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    contextMenu.entryName = row.entryName
                                    contextMenu.entryIsDir = row.entryIsDir
                                    contextMenu.entryPath = row.entryPath
                                    contextMenu.open()
                                    return
                                }
                                // Single click selects one item; platform modifier toggles multi-select.
                                root.selectPath(row.entryPath, mouse.modifiers)
                            }
                        }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    visible: entriesModel.count === 0
                    text: qsTr("This folder is empty")
                    color: App.Theme.textMuted
                    font.pixelSize: 13
                }

                Menu {
                    id: contextMenu
                    property string entryName: ""
                    property string entryPath: ""
                    property bool entryIsDir: false

                    MenuItem {
                        text: qsTr("Open")
                        onTriggered: {
                            if (contextMenu.entryIsDir)
                                root.navigateToPath(contextMenu.entryPath, true)
                            else
                                root.openFileOnDevice(contextMenu.entryName)
                        }
                    }

                    MenuItem {
                        text: qsTr("Export")
                        onTriggered: {
                            if (!root.isSelected(contextMenu.entryPath))
                                root.selectedPaths = [contextMenu.entryPath]
                            root.updateActionEnabled()
                            exportDialog.open()
                        }
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: qsTr("Delete")
                        onTriggered: {
                            if (!root.isSelected(contextMenu.entryPath))
                                root.selectedPaths = [contextMenu.entryPath]
                            root.updateActionEnabled()
                            confirmDelete.open()
                        }
                    }
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
            Text { text: qsTr("Path: ") + root.currentPath; color: App.Theme.textMuted }
        }

        onAccepted: {
            var alias = (favAlias.text || "").trim()
            if (alias.length === 0) return
            root.favoritePlaceAdded(alias, root.currentPath)
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
            Text { text: qsTr("Count: ") + root.selectedPaths.length; color: App.Theme.textMuted }
        }

        onAccepted: root.deleteSelected()
    }

    FolderDialog {
        id: exportDialog
        title: qsTr("Choose Export Folder")
        onAccepted: root.startExport(QmlUtils.url_to_path(selectedFolder))
    }

    FileDialog {
        id: importDialog
        title: qsTr("Choose Files to Import")
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            var paths = []
            for (var i = 0; i < selectedFiles.length; i++)
                paths.push(QmlUtils.url_to_path(selectedFiles[i]))
            root.startImport(paths)
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
