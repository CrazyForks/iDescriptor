import ".."
import "../base"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    required property string udid
    required property var device
    property bool loaded: false
    property bool loading: true
    property bool fileSharingOnly: true
    property string errorMessage: ""
    property string searchText: ""
    property string selectedBundleId: ""
    property var houseArrestAfcClient: null
    property bool tabsDisabled: false
    property var iconForBundleId: ({})
    property var appTabForBundleId: ({})

    function init() {
        if (loaded)
            return ;

        loaded = true;
        refresh();
    }

    function refresh() {
        root.loading = true;
        root.errorMessage = "";
        root.selectedBundleId = "";
        root.houseArrestAfcClient = null;
        allAppsModel.clear();
        filteredAppsModel.clear();
        updateViewState();
        if (!root.device || !root.device.service_manager) {
            root.loading = false;
            root.errorMessage = qsTr("Failed to retrieve installed apps.");
            updateViewState();
            return ;
        }
        root.device.service_manager.fetch_installed_apps();
    }

    function updateViewState() {
        if (root.loading) {
            stateView.viewState = StateView.State.Loading;
            return ;
        }
        if (root.errorMessage.length > 0) {
            stateView.errorText = root.errorMessage;
            stateView.viewState = StateView.State.Error;
            return ;
        }
        stateView.viewState = StateView.State.Content;
    }

    function appDisplayName(app) {
        var name = app.displayName && app.displayName.length > 0 ? app.displayName : app.bundleId;
        if (app.appType === "System")
            name += qsTr(" (System)");

        return name;
    }

    function appendApp(appJson) {
        var app = null;
        try {
            app = JSON.parse(appJson);
        } catch (e) {
            console.log("InstalledApps: failed to parse app JSON:", e);
            return ;
        }
        var bundleId = app.bundle_id || "";
        /*
            Always fails to load Fitness app container
            even though file sharing is enabled
        */
        if (bundleId.length === 0 || bundleId === "com.apple.Fitness")
            return ;

        allAppsModel.append({
            "appName": appDisplayName({
                "displayName": app.CFBundleDisplayName || "",
                "bundleId": bundleId,
                "appType": app.app_type || ""
            }),
            "displayName": app.CFBundleDisplayName || bundleId,
            "bundleId": bundleId,
            "version": app.CFBundleShortVersionString || "",
            "appType": app.app_type || "",
            "fileSharingEnabled": !!app.UIFileSharingEnabled,
            "iconSource": ""
        });
    }

    // FIXME: use a proper filtering model
    function rebuildFilteredApps() {
        filteredAppsModel.clear();
        var needle = root.searchText.toLowerCase();
        for (var i = 0; i < allAppsModel.count; i++) {
            var app = allAppsModel.get(i);
            if (root.fileSharingOnly && !app.fileSharingEnabled)
                continue;

            if (needle.length > 0) {
                var name = (app.appName || "").toLowerCase();
                var bundleId = (app.bundleId || "").toLowerCase();
                if (name.indexOf(needle) === -1 && bundleId.indexOf(needle) === -1)
                    continue;

            }
            filteredAppsModel.append({
                "appName": app.appName,
                "displayName": app.displayName,
                "bundleId": app.bundleId,
                "version": app.version,
                "appType": app.appType,
                "fileSharingEnabled": app.fileSharingEnabled,
                "iconSource" : app.iconSource,
                "selected": root.selectedBundleId === app.bundleId
            });
        }
        if (filteredAppsModel.count > 0 && !root.selectedBundleId)
            selectApp(filteredAppsModel.get(0).bundleId);
    }

    function selectApp(bundleId) {
        if (!bundleId || bundleId.length === 0 || root.tabsDisabled)
            return ;

        root.selectedBundleId = bundleId;
        root.tabsDisabled = true;
        root.houseArrestAfcClient = null;

        var client = serviceFactory.create_hause_arrest_afc_client(root.udid, bundleId);
        root.houseArrestAfcClient = client;
        root.tabsDisabled = false;
        if (client === null)
            // FIXME: expose a success/error signal for house arrest session creation if this factory can fail asynchronously.
            containerMessage.text = qsTr("No data available for this app.");

    }

    anchors.fill: parent
    Component.onCompleted: {
        updateViewState();
        loadTimer.start();
    }

    Timer {
        id: loadTimer
        interval: 300
        repeat: false
        onTriggered: root.init()
    }

    Connections {
        function onInstalledAppsRetrieved(success, apps) {
            allAppsModel.clear();
            filteredAppsModel.clear();
            if (!success) {
                root.loading = false;
                root.errorMessage = qsTr("Failed to retrieve installed apps.");
                updateViewState();
                return ;
            }
            for (var key in apps) appendApp(apps[key])
            root.loading = false;
            if (allAppsModel.count === 0)
            // FIXME: return success as well
                root.errorMessage = qsTr("No apps found or failed to retrieve apps.");
            else
                root.errorMessage = "";
            updateViewState();
            rebuildFilteredApps();
        }

        target: root.device && root.device.service_manager ? root.device.service_manager : null
    }

    Connections {
        target : root.device.sb_client

        function onApp_icon_loaded(bundleId, iconData) {
            var tab = root.appTabForBundleId[bundleId];
            if (tab) {
                tab.iconSource = iconData;
            }
        }
    }

    ListModel {
        id: allAppsModel
    }

    ListModel {
        id: filteredAppsModel
    }

    StateView {
        id: stateView
        autoSwitchContent: false
        anchors.fill: parent
        viewState: StateView.State.Loading
        retryable: true
        onRetryRequested: root.refresh()

        //TODO: move to a seperate comp
        contentItem: SplitView {
            orientation: Qt.Horizontal
            anchors.fill: parent
            spacing: 0

            handle: Rectangle {
                implicitWidth: 7
                radius: 10
                color: SplitHandle.pressed
                    ? Theme.focus
                    : SplitHandle.hovered ? Theme.selectionStroke : Theme.sidebarDivider

                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: parent.height
                    color: Theme.sidebarDivider
                }
            }

            Rectangle {
                SplitView.preferredWidth: 275
                SplitView.minimumWidth: 100
                SplitView.maximumWidth: 300
                SplitView.fillHeight: true
                color: "transparent"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 60
                        Layout.leftMargin: 5
                        Layout.rightMargin: 5
                        Layout.bottomMargin: 5
                        spacing: 8

                        TextField {
                            id: searchEdit

                            Layout.fillWidth: true
                            placeholderText: qsTr("Search apps...")
                            text: root.searchText
                            onTextChanged: {
                                root.searchText = text;
                                rebuildFilteredApps();
                            }
                        }

                        CheckBox {
                            id: fileSharingCheck

                            checked: root.fileSharingOnly
                            text: qsTr("File Sharing")
                            font.pixelSize: 10
                            onToggled: {
                                root.fileSharingOnly = checked;
                                rebuildFilteredApps();
                            }
                        }

                    }

                    ListView {
                        id: appList

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 10
                        boundsBehavior: Flickable.StopAtBounds
                        model: filteredAppsModel

                        delegate: ItemDelegate {
                            width: appList.width
                            height: 60

                            AppTab {
                                id : tab
                                Component.onCompleted: {
                                    root.appTabForBundleId[model.bundleId] = tab;
                                }
                                device: root.device
                                width: appList.width
                                appName: model.appName
                                bundleId: model.bundleId
                                version: model.version
                                selected: root.selectedBundleId === model.bundleId
                                enabled: !root.tabsDisabled
                                iconSource: model.iconSource
                                onAppClicked: (bundleId) => {
                                    return root.selectApp(bundleId);
                                }
                            }
                        }

                    }

                }

            }

            Item {
                SplitView.fillWidth: true
                SplitView.fillHeight: true

                FileExplorer {
                    id: explorer

                    anchors.fill: parent
                    udid: root.device.info["UniqueDeviceID"]
                    afcClient: root.houseArrestAfcClient
                    rootPath: "/Documents"
                    favEnabled: false
                    visible: !!root.houseArrestAfcClient
                }

                Text {
                    id: containerMessage

                    anchors.centerIn: parent
                    width: Math.min(parent.width * 0.8, 420)
                    text: root.selectedBundleId.length > 0 ? qsTr("No data available for this app.") : qsTr("Select an app to browse its documents.")
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: Qt.rgba(palette.text.r, palette.text.g, palette.text.b, 0.72)
                    visible: !root.houseArrestAfcClient
                }

            }

        }

    }

}
