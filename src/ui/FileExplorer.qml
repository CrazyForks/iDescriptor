import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Controls.impl
import QtQuick.Dialogs
import QtCore
import "." as App
import "./base"

Item {
    id: root
    anchors.fill: parent

    property var afcClient: null
    required property string udid
    property bool useAfc2: false

    property bool favEnabled: true
    property bool allowDirectoryExport: true
    property string rootPath: "/"

    property string currentPath: "/"
    property bool loading: false
    property string errorMessage: ""
    property bool refreshAfterLoad: false
    property var pendingImportJobs: ({})
    property var pendingExternalOpenJobs: ({})
    property bool deleting: false
    property string pendingDeleteRequestId: ""
    property int selectedCount: 0
    property int selectedFileCount: 0
    property int selectedFolderCount: 0

    readonly property bool busy: loading || deleting

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

    function requestRefresh() {
        if (loading) {
            refreshAfterLoad = true
            return
        }

        refresh()
    }

    function finishDirectoryLoad() {
        loading = false

        if (!refreshAfterLoad)
            return

        refreshAfterLoad = false
        Qt.callLater(function() {
            if (root.afcClient)
                root.refresh()
        })
    }

    function importContextKey() {
        if (afcClient && afcClient.bundle_id)
            return udid + "|house-arrest|" + afcClient.bundle_id

        return udid + (useAfc2 ? "|afc2" : "|afc")
    }

    function hasPendingImportFor(destinationPath, contextKey) {
        for (var jobId in pendingImportJobs) {
            var job = pendingImportJobs[jobId]
            if (job.destinationPath === destinationPath
                    && job.contextKey === contextKey)
                return true
        }

        return false
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
        const path = fullPath(name)

        if (Helpers.is_previewable(name)) {
            const comp = Qt.createComponent("PreviewWindow.qml")
            if (comp.status === Component.Ready) {
                console.log("Opening preview for", path)
                console.log("afcClient defined?", !!afcClient)
                console.log("root.udid:", root.udid)
                const win = comp.createObject(root, {
                    filePath: path,
                    udid: root.udid,
                    afcClient: root.afcClient,
                    useAfc2: root.useAfc2
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

        confirmOpenExternally(path, name, false)
    }

    function confirmOpenExternally(remotePath, displayName, requested) {
        if (!afcClient || !ioManager || !root.udid)
            return;
        App.Helpers.messageBox(
            root,
            qsTr("Open Externally"),
            requested ? qsTr("Export %1 to a temporary folder and open it with the default application?").arg(displayName) : qsTr("This file type cannot be previewed would like to export to a temporary folder and open it with the default application?"),
            MessageDialog.Yes | MessageDialog.No,
            function(button) {
                if (button === MessageDialog.Yes)
                    root.startExternalOpenExport(remotePath, displayName)
            })
    }

    function startExternalOpenExport(remotePath, displayName) {
        if (!ioManager || !root.udid)
            return

        const jobId = String(QmlUtils.generate_uuid())
        const tempRoot = QmlUtils.url_to_path(
            StandardPaths.writableLocation(StandardPaths.TempLocation))
        if (!tempRoot || tempRoot.length === 0) {
            App.Helpers.showError(
                root,
                qsTr("The system temporary folder could not be located."))
            return
        }



        const destinationDir = QmlUtils.join_path(
            tempRoot,
            "idescriptor-open-" + jobId)
        root.pendingExternalOpenJobs[jobId] = {
            "displayName": displayName,
            "remotePath": remotePath,
            "destinationDir": destinationDir
        }



        const isHouseArrest = !!(afcClient && afcClient.bundle_id)


        App.StatusWindow.addProcess(
            jobId,
            isHouseArrest ? qsTr("Exporting for External Open from %1").arg(afcClient.bundle_id) : qsTr("Exporting for External Open"),
            qsTr("Export"),
            1,
            destinationDir
        )

        if (isHouseArrest) {
            ioManager.start_export_with_hause_arrest_afc(
                root.udid,
                jobId,
                [remotePath],
                destinationDir,
                afcClient.bundle_id,
                false)
        } else if (root.useAfc2) {
            ioManager.start_export_with_afc2(
                root.udid,
                jobId,
                [remotePath],
                destinationDir,
                false)
        } else {
            ioManager.start_export(
                root.udid,
                jobId,
                [remotePath],
                destinationDir,
                false)
        }
    }

    ListModel { id: entriesModel }

    function setEntrySelected(index, selected) {
        if (index < 0 || index >= entriesModel.count)
            return
        entriesModel.setProperty(index, "selected", selected)
    }

    function updateSelectionCounts() {
        var files = 0
        var folders = 0
        for (var index = 0; index < entriesModel.count; ++index) {
            var entry = entriesModel.get(index)
            if (!entry.selected)
                continue
            if (entry.isDir)
                ++folders
            else
                ++files
        }

        selectedFileCount = files
        selectedFolderCount = folders
        selectedCount = files + folders
    }

    function selectedPaths() {
        var paths = []
        for (var index = 0; index < entriesModel.count; ++index) {
            var entry = entriesModel.get(index)
            if (entry.selected)
                paths.push(entry.path)
        }
        return paths
    }

    function requestDeleteSelected() {
        if (!afcClient || deleting || selectedCount === 0)
            return

        const paths = selectedPaths()
        const recursiveDirectoriesConfirmed = selectedFolderCount > 0
        App.Helpers.showDeleteConfirmation(
            root.Window.window,
            selectedFileCount,
            selectedFolderCount,
            function() {
                root.startDelete(paths, recursiveDirectoriesConfirmed)
            }
        )
    }

    function startDelete(paths, recursiveDirectoriesConfirmed) {
        if (!afcClient || deleting || paths.length === 0)
            return

        pendingDeleteRequestId = QmlUtils.generate_uuid()
        deleting = true
        errorMessage = ""
        afcClient.delete_paths(
            pendingDeleteRequestId,
            paths,
            recursiveDirectoriesConfirmed
        )
    }

    function startExport(destinationDir) {
        const paths = selectedPaths()
        if (!ioManager || !root.udid || paths.length === 0)
            return

        const jobId = QmlUtils.generate_uuid()
        const isHouseArrest = !!(afcClient && afcClient.bundle_id)
        App.StatusWindow.addProcess(
            jobId,
            isHouseArrest ? qsTr("Exporting File(s) from %1").arg(afcClient.bundle_id) : qsTr("Exporting File(s)"),
            qsTr("Export"),
            paths.length,
            destinationDir
        )
        if (isHouseArrest)
            ioManager.start_export_with_hause_arrest_afc(root.udid, jobId, paths, destinationDir, afcClient.bundle_id, allowDirectoryExport)
        else if (root.useAfc2)
            ioManager.start_export_with_afc2(root.udid, jobId, paths, destinationDir, allowDirectoryExport)
        else
            ioManager.start_export(root.udid, jobId, paths, destinationDir, allowDirectoryExport)
    }

    function startImport(localPaths) {
        if (!ioManager || !root.udid || localPaths.length === 0)
            return

        const jobId = QmlUtils.generate_uuid()
        const destinationPath = normalizePath(currentPath)
        pendingImportJobs[String(jobId)] = {
            "destinationPath": destinationPath,
            "contextKey": importContextKey()
        }
        const isHouseArrest = !!(afcClient && afcClient.bundle_id)
        App.StatusWindow.addProcess(
            jobId,
            isHouseArrest ? qsTr("Importing Files to %1").arg(afcClient.bundle_id) : qsTr("Importing Files"),
            qsTr("Import"),
            localPaths.length,
            destinationPath
        )
        if (isHouseArrest)
            ioManager.start_import_with_hause_arrest_afc(root.udid, jobId, localPaths, destinationPath, afcClient.bundle_id)
        else if (root.useAfc2)
            ioManager.start_import_with_afc2(root.udid, jobId, localPaths, destinationPath)
        else
            ioManager.start_import(root.udid, jobId, localPaths, destinationPath)
    }

    Connections {
        target: ioManager
        enabled: !!ioManager

        function onExportItemFinished(jobId, fileName, destinationPath, success, bytesTransferred, errorMessage) {
            const key = String(jobId)
            const job = root.pendingExternalOpenJobs[key]
            if (job === undefined)
                return

            delete root.pendingExternalOpenJobs[key]

            if (!success) {
                App.Helpers.showError(
                    root.Window.window,
                    errorMessage && errorMessage.length > 0
                        ? errorMessage
                        : qsTr("%1 could not be exported.").arg(job.displayName))
                return
            }

            const opened = Qt.openUrlExternally(
                App.Helpers.toFileUrl(destinationPath))
            if (!opened) {
                App.Helpers.showError(
                    root.Window.window,
                    qsTr("%1 was exported, but no application could open it.").arg(job.displayName))
            }
        }

        function onExportJobFinished(jobId, cancelled, successfulItems, failedItems, totalBytes) {
            const key = String(jobId)
            const job = root.pendingExternalOpenJobs[key]
            if (job === undefined)
                return

            // A successful item result normally removes the request first. If
            // the request is still present, the job ended before producing one.
            delete root.pendingExternalOpenJobs[key]
            App.Helpers.showError(
                root.Window.window,
                cancelled
                    ? qsTr("Opening %1 was cancelled or could not be started.").arg(job.displayName)
                    : qsTr("%1 could not be exported for opening.").arg(job.displayName))
        }

        function onImportJobFinished(jobId, cancelled, successfulItems, failedItems, totalBytes) {
            const key = String(jobId)
            const job = root.pendingImportJobs[key]
            if (job === undefined)
                return

            delete root.pendingImportJobs[key]

            if (job.contextKey !== root.importContextKey()
                    || job.destinationPath !== root.normalizePath(root.currentPath))
                return

            // Coalesce concurrent imports targeting the currently displayed directory.
            if (!root.hasPendingImportFor(job.destinationPath, job.contextKey))
                root.requestRefresh()
        }
    }

    Connections {
        target: afcClient
        enabled: !!afcClient

        function onCheck_is_dir_and_list_finished(success, entries) {
            selectionLayer.reset()
            entriesModel.clear()

            if (!success) {
                root.errorMessage = qsTr("Failed to load directory.")
                root.finishDirectoryLoad()
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
                var item = {
                    "name": name,
                    "path": root.fullPath(name),
                    "isDir": isDir,
                    "selected": false,
                    "iconSource": iconSource
                }
                if (isDir) dirs.push(item); else files.push(item)
            }

            for (var d = 0; d < dirs.length; d++) entriesModel.append(dirs[d])
            for (var f = 0; f < files.length; f++) entriesModel.append(files[f])

            root.errorMessage = ""
            root.updateSelectionCounts()
            root.updateNavigationEnabled()
            root.finishDirectoryLoad()
        }

        function onDeletePathsFinished(requestId, successfulItems, failedItems, firstError) {
            if (requestId !== root.pendingDeleteRequestId)
                return

            root.pendingDeleteRequestId = ""
            root.deleting = false
            selectionLayer.clearSelection()
            root.refresh()

            const messageParent = root.Window.window.contentItem
            if (failedItems === 0) {
                App.Helpers.showInfo(
                    messageParent,
                    qsTr("%1 item(s) were deleted successfully.").arg(successfulItems)
                )
            } else if (successfulItems > 0) {
                var partialMessage = qsTr("%1 item(s) were deleted. %2 item(s) could not be deleted.")
                    .arg(successfulItems).arg(failedItems)
                if (firstError)
                    partialMessage += "\n\n" + firstError
                App.Helpers.showWarning(messageParent, partialMessage)
            } else {
                var failureMessage = qsTr("The selected items could not be deleted.")
                if (firstError)
                    failureMessage += "\n\n" + firstError
                App.Helpers.showError(messageParent, failureMessage)
            }
        }

    }

    onAfcClientChanged: {
        refreshAfterLoad = false
        deleting = false
        pendingDeleteRequestId = ""
        backStack = []
        forwardStack = []
        selectionLayer.reset()
        entriesModel.clear()
        updateSelectionCounts()
        currentPath = normalizePath(rootPath)
        addressBar.text = currentPath
        if (afcClient) refresh()
        else errorMessage = qsTr("AFC client is not available.")
        updateNavigationEnabled()
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
                    enabled: !!root.afcClient && !root.busy
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
                    enabled: !!root.afcClient && !root.busy
                    iconSource: "qrc:/resources/icons/lets-icons_import.svg"
                    tooltip: qsTr("Import")
                    onClicked: importDialog.open()
                }

                ExplorerToolButton {
                    id: exportBtn
                    enabled: root.selectedCount > 0 && !root.busy
                    iconSource: "qrc:/resources/icons/ph_export.svg"
                    tooltip: qsTr("Export")
                    onClicked: exportDialog.open()
                }

                ExplorerToolButton {
                    id: deleteBtn
                    enabled: root.selectedCount > 0 && !root.busy
                    iconSource: "qrc:/resources/icons/material-symbols_delete.svg"
                    tooltip: qsTr("Delete")
                    onClicked: root.requestDeleteSelected()
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
            viewState: root.busy
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
                        property string entryPath: model.path
                        property bool entrySelected: model.selected

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
                                    if (!row.entrySelected)
                                        selectionLayer.selectOnly(index)
                                    contextMenu.entryName = row.entryName
                                    contextMenu.entryIsDir = row.entryIsDir
                                    contextMenu.entryPath = row.entryPath
                                    contextMenu.entryIndex = index
                                    contextMenu.popup(mouseArea, Qt.point(mouse.x, mouse.y))
                                    return
                                }
                            }
                        }
                    }
                }

                FileExplorerSelection {
                    id: selectionLayer

                    anchors.fill: listView
                    z: 2
                    visible: !root.busy
                    targetView: listView
                    itemCount: entriesModel.count
                    rowHeight: 44
                    isItemSelected: (index) => entriesModel.get(index).selected
                    setItemSelected: (index, selected) => root.setEntrySelected(index, selected)
                    onSelectionUpdated: root.updateSelectionCounts()
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
                    property int entryIndex: -1

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
                        visible: !contextMenu.entryIsDir
                        text: qsTr("Open Externally")
                        onTriggered: root.confirmOpenExternally(
                            contextMenu.entryPath,
                            contextMenu.entryName, true)
                    }

                    MenuItem {
                        text: qsTr("Export")
                        onTriggered: {
                            exportDialog.open()
                        }
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: qsTr("Get Info")
                        onTriggered: App.Helpers.showFileInfo(
                            root.Window.window,
                            root.afcClient,
                            contextMenu.entryPath,
                            contextMenu.entryName
                        )
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: qsTr("Delete")
                        onTriggered: root.requestDeleteSelected()
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
