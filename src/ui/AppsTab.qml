import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "./app-store/"
import "./base"
import "." as App

Item {
    id: root
    anchors.fill: parent
    clip:true

    readonly property string sponsorsUrl: "https://raw.githubusercontent.com/iDescriptor/iDescriptor/refs/heads/main/sponsors.json"

    property bool loading: true
    property string error: ""
    property string email: ""
    property bool isLoggedIn: email.length > 0
    property bool sponsorsFetched: false

    property string searchTerm: ""
    property bool searchLoading: false
    property bool searchError: false
    property string searchErrorText: ""

    property string bundleId: ""
    property string appName: ""


    ListModel { id: searchResultsModel }
    ListModel { id: appModel }

    InstallAppPopup {
        id: installPopup
        bundleId: root.bundleId
        appName: root.appName
        anchors.centerIn: parent
    }

    GetIpaPopup {
        id: getIpaPopup
        bundleId: root.bundleId
        appName: root.appName
        anchors.centerIn: parent
    }

    LoginDialog {
        id: loginDialog
        anchors.centerIn: parent
    }

    function openInstallPopup(bundleId, appName) {
        root.bundleId = bundleId
        root.appName = appName
        installPopup.open()
    }

    function openGetIpaPopup(bundleId, appName) {
        root.bundleId = bundleId
        root.appName = appName
        getIpaPopup.open()
    }

    function clearApps() { appModel.clear() }

    function addApp(obj) { appModel.append(obj) }

    function pickLastVersionKey(obj) {
        var keys = Object.keys(obj || {})
        if (!keys.length) return ""
        keys.sort()
        // FIXME: use semantic version matching instead of last key.
        return keys[keys.length - 1]
    }

    function addSponsors(tierObj, label, color) {
        if (!tierObj || !tierObj.members) return
        for (var i = 0; i < tierObj.members.length; ++i) {
            var m = tierObj.members[i]
            addApp({
                name: m.name || "",
                bundleId: m.bundleId || "",
                description: m.description || "",
                logoUrl: m.logo || "",
                websiteUrl: m.url || "",
                useBundleIdForIcon: m.useBundleIdForIcon !== false,
                sponsorLabel: label,
                sponsorColor: color
            })
        }
    }

    function addDefaultApps() {
        addApp({ name: "Instagram", bundleId: "com.burbn.instagram", description: "Photo & Video sharing social network", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" })
        addApp({ name: "Spotify", bundleId: "com.spotify.client", description: "Music streaming and podcast platform", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" })
        addApp({ name: "YouTube", bundleId: "com.google.ios.youtube", description: "Video sharing and streaming platform", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" })
        addApp({ name: "X", bundleId: "com.atebits.Tweetie2", description: "Social media and microblogging", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" })
        addApp({ name: "TikTok", bundleId: "com.zhiliaoapp.musically", description: "Short-form video hosting service", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" })
        addApp({ name: "Twitch", bundleId: "tv.twitch", description: "Live streaming platform", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" })
        addApp({ name: "Telegram", bundleId: "ph.telegra.Telegraph", description: "Cloud-based instant messaging", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" })
        addApp({ name: "Reddit", bundleId: "com.reddit.Reddit", description: "Social news aggregation platform", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" })
    }

    function fetchSponsors() {
        loading = true
        error = ""
        clearApps()

        var xhr = new XMLHttpRequest()
        xhr.open("GET", sponsorsUrl)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return

            if (xhr.status === 200) {
                try {
                    var rootObj = JSON.parse(xhr.responseText)
                    // FIXME: don't pick the last version
                    var key = pickLastVersionKey(rootObj)
                    var versioned = key ? rootObj[key] : null
                    var sponsors = versioned && versioned.sponsors ? versioned.sponsors : null

                    if (sponsors) {
                        addSponsors(sponsors.platinum, "Platinum", "#E5E4E2")
                        addSponsors(sponsors.gold, "Gold", "#D4AF37")
                        addSponsors(sponsors.silver, "Silver", "#C0C0C0")
                        addSponsors(sponsors.bronze, "Bronze", "#CD7F32")
                    }
                } catch (e) {
                    error = "Failed to parse sponsors JSON."
                }
            } else {
                error = "Failed to fetch sponsors."
            }

            addDefaultApps()
            loading = false
        }
        xhr.send()
    }

    function openDetails(app) {
        if (!app || !app.bundleId) return
        nav.push(detailsHostComponent, { app: app })
    }

    Component.onCompleted: {
        // FIXME: show keychain/cred dialog.
        apps.init()
    }

    Connections {
        target: apps

        function onStateChanged() {
            var s = apps.state
            if (!s) return
            email = s.email || ""
            if (s.error && !loginDialog.visible) error = s.error
            if (s.init && !root.sponsorsFetched) {
                root.sponsorsFetched = true
                fetchSponsors()
            }
        }

        function onSearch_ready(searchTerm, success, res) {
            if (searchTerm !== root.searchTerm.trim()) return

            root.searchLoading = false
            searchResultsModel.clear()

            if (!success) {
                console.error("Search failed for term:", searchTerm)
                searchError = true
                searchErrorText = qsTr("Search failed.")
                return
            }

            try {
                const parsedRes = JSON.parse(res)
                if (!parsedRes || !parsedRes.results || !Array.isArray(parsedRes.results)) {
                    console.error("Invalid search results format: 'results' array not found or not an array.", res)
                    searchError = true
                    searchErrorText = qsTr("Search returned an invalid response.")
                    return
                }

                searchError = false
                searchErrorText = ""

                for (var i = 0; i < parsedRes.results.length; ++i) {
                    const item = parsedRes.results[i]
                    searchResultsModel.append({
                        id: item.id || 0,
                        bundleId: item.bundle_id || "",
                        name: item.name || "",
                        price: item.price || 0,
                        description: item.bundle_id || "",
                        logoUrl: "",
                        websiteUrl: "",
                        useBundleIdForIcon: true,
                        sponsorLabel: "",
                        sponsorColor: ""
                    })
                }
            } catch (e) {
                searchError = true
                searchErrorText = qsTr("Failed to parse search results.")
            }
        }
    }

    StackView {
        id: nav
        anchors.fill: parent
        initialItem: mainPageComponent
        clip: true

        pushEnter: Transition {
            PropertyAnimation { property: "x"; from: root.width; to: 0; duration: 320; easing.type: Easing.OutCubic }
        }
        pushExit: Transition {
            PropertyAnimation { property: "x"; from: 0; to: -root.width; duration: 320; easing.type: Easing.OutCubic }
            PropertyAnimation { property: "opacity"; from: 1; to: 0.55; duration: 320; easing.type: Easing.OutCubic }
        }
        popEnter: Transition {
            PropertyAnimation { property: "x"; from: -root.width; to: 0; duration: 280; easing.type: Easing.OutCubic }
            PropertyAnimation { property: "opacity"; from: 0.55; to: 1; duration: 280; easing.type: Easing.OutCubic }
        }
        popExit: Transition {
            PropertyAnimation { property: "x"; from: 0; to: nav.width; duration: 280; easing.type: Easing.OutCubic }
        }
    }

    Component {
        id: mainPageComponent

        ColumnLayout {
            spacing: 0

            function showCatalog() {
                root.searchLoading = false
                root.searchError = false
                root.searchErrorText = ""
                searchResultsModel.clear()
                if (!resultStack.currentItem || resultStack.currentItem.objectName !== "catalogPage")
                    resultStack.replace(catalogPageComponent)
            }

            function showSearch() {
                if (!resultStack.currentItem || resultStack.currentItem.objectName !== "searchPage")
                    resultStack.replace(searchPageComponent)
            }

            Component.onCompleted: resultStack.push(catalogPageComponent)

            Timer {
                id: searchTimer
                interval: 260
                repeat: false
                onTriggered: {
                    var term = root.searchTerm.trim()
                    if (!term.length) {
                        showCatalog()
                        return
                    }

                    showSearch()

                    root.searchLoading = true
                    root.searchError = false
                    root.searchErrorText = ""
                    searchResultsModel.clear()
                    apps.search(term)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 18
                spacing: 12

                TextField {
                    id: searchField
                    Layout.preferredWidth: 200
                    placeholderText: qsTr("Search for apps...")
                    onTextChanged: {
                        root.searchTerm = text
                        searchTimer.restart()
                    }
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: isLoggedIn ? qsTr("Signed in as %1").arg(email) : qsTr("Not signed in")
                    color: App.Theme.textMuted
                }

                Button {
                    text: isLoggedIn ? qsTr("Sign Out") : qsTr("Sign In")
                    onClicked: {
                        if (isLoggedIn)
                            apps.sign_out()
                        else
                            loginDialog.open()
                    }
                }
            }

            StackView {
                id: resultStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                replaceEnter: Transition {
                    PropertyAnimation { property: "opacity"; from: 0; to: 1; duration: 180 }
                }
                replaceExit: Transition {
                    PropertyAnimation { property: "opacity"; from: 1; to: 0; duration: 120 }
                }
            }
        }
    }

    Component {
        id: catalogPageComponent

        StateView {
            objectName: "catalogPage"
            autoSwitchContent: false
            retryable: false
            viewState: root.loading ? StateView.State.Loading : StateView.State.Content
            errorText: root.error

            contentItem: Item {
                anchors.fill: parent

                ScrollView {
                    anchors.fill: parent
                    clip: true

                    GridView {
                        id: catalogGrid
                        anchors.fill: parent
                        anchors.margins: 18
                        cellWidth: Math.max(270, width / 3)
                        cellHeight: 140
                        model: appModel

                        delegate: Item {
                            width: catalogGrid.cellWidth - 12
                            height: catalogGrid.cellHeight - 12

                            AppItem {
                                anchors.fill: parent
                                name: model.name
                                bundleId: model.bundleId
                                description: model.description
                                logoUrl: model.logoUrl
                                websiteUrl: model.websiteUrl
                                useBundleIdForIcon: model.useBundleIdForIcon
                                sponsorLabel: model.sponsorLabel
                                sponsorColor: model.sponsorColor
                                onSelected: function(app) { root.openDetails(app) }
                                onInstallRequested: function(bundleId, appName) { root.openInstallPopup(bundleId, appName) }
                                onGetIpaRequested: function(bundleId, appName) { root.openGetIpaPopup(bundleId, appName) }
                            }
                        }
                    }
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    text: root.error
                    color: "#c00"
                    visible: root.error.length > 0 && !root.loading
                }
            }
        }
    }

    Component {
        id: searchPageComponent

        StateView {
            objectName: "searchPage"
            autoSwitchContent: false
            retryable: false
            viewState: root.searchLoading
                       ? StateView.State.Loading
                       : (root.searchError ? StateView.State.Error : StateView.State.Content)
            errorText: root.searchErrorText

            contentItem: Item {
                anchors.fill: parent

                ScrollView {
                    anchors.fill: parent
                    clip: true

                    ListView {
                        id: searchList
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 10
                        model: searchResultsModel

                        delegate: Item {
                            width: searchList.width
                            height: 112
                            AppItem {
                                anchors.fill: parent
                                name: model.name
                                bundleId: model.bundleId
                                description: model.description
                                logoUrl: model.logoUrl
                                websiteUrl: model.websiteUrl
                                useBundleIdForIcon: model.useBundleIdForIcon
                                sponsorLabel: model.sponsorLabel
                                sponsorColor: model.sponsorColor
                                onSelected: function(app) { root.openDetails(app) }
                            }
                        }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    text: qsTr("No results")
                    color: "#6e6e73"
                    visible: !root.searchLoading && !root.searchError && searchResultsModel.count === 0
                }
            }
        }
    }

    Component {
        id: detailsHostComponent

        Item {
            required property var app

            Loader {
                id: detailsLoader
                anchors.fill: parent
                property var detailsApp: app
                active: true
                sourceComponent: AppDetails {
                    app: detailsLoader.detailsApp
                    onBackRequested: nav.pop()
                }
            }
        }
    }
}
