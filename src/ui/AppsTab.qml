import QtQuick 
import QtQuick.Controls
import QtQuick.Layouts 
import Qt5Compat.GraphicalEffects
import QtQuick.Controls.impl 
import "./app-store/"
import "./base"


StateView {
    id: root
    anchors.fill: parent

    // readonly property Apps apps
    readonly property string sponsorsUrl: "https://raw.githubusercontent.com/iDescriptor/iDescriptor/refs/heads/main/sponsors.json"

    property bool loading: true
    property string error: ""
    property string email: ""
    property bool isLoggedIn: email.length > 0

    property string searchTerm: ""
    property bool searchError: false

    ListModel { id : searchResultsModel }
    ListModel { id: appModel }

    function clearApps() { appModel.clear(); }

    function addApp(obj) { appModel.append(obj); }

    function pickLastVersionKey(obj) {
        var keys = Object.keys(obj || {});
        if (!keys.length) return "";
        keys.sort();
        // FIXME: use semantic version matching instead of last key.
        return keys[keys.length - 1];
    }

    function addSponsors(tierObj, label, color) {
        if (!tierObj || !tierObj.members) return;
        for (var i = 0; i < tierObj.members.length; ++i) {
            var m = tierObj.members[i];
            addApp({
                name: m.name || "",
                bundleId: m.bundleId || "",
                description: m.description || "",
                logoUrl: m.logo || "",
                websiteUrl: m.url || "",
                useBundleIdForIcon: m.useBundleIdForIcon !== false,
                sponsorLabel: label,
                sponsorColor: color
            });
        }
    }

    function addDefaultApps() {
        addApp({ name: "Instagram", bundleId: "com.burbn.instagram", description: "Photo & Video sharing social network", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" });
        addApp({ name: "Spotify", bundleId: "com.spotify.client", description: "Music streaming and podcast platform", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" });
        addApp({ name: "YouTube", bundleId: "com.google.ios.youtube", description: "Video sharing and streaming platform", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" });
        addApp({ name: "X", bundleId: "com.atebits.Tweetie2", description: "Social media and microblogging", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" });
        addApp({ name: "TikTok", bundleId: "com.zhiliaoapp.musically", description: "Short-form video hosting service", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" });
        addApp({ name: "Twitch", bundleId: "tv.twitch", description: "Live streaming platform", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" });
        addApp({ name: "Telegram", bundleId: "ph.telegra.Telegraph", description: "Cloud-based instant messaging", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" });
        addApp({ name: "Reddit", bundleId: "com.reddit.Reddit", description: "Social news aggregation platform", logoUrl: "", websiteUrl: "", useBundleIdForIcon: true, sponsorLabel: "", sponsorColor: "" });
    }

    function fetchSponsors() {
        loading = true;
        error = "";
        clearApps();

        var xhr = new XMLHttpRequest();
        xhr.open("GET", sponsorsUrl);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;

            if (xhr.status === 200) {
                try {
                    var rootObj = JSON.parse(xhr.responseText);
                    // FIXME: don't pick the last version
                    var key = pickLastVersionKey(rootObj);
                    var versioned = key ? rootObj[key] : null;
                    var sponsors = versioned && versioned.sponsors ? versioned.sponsors : null;

                    if (sponsors) {
                        addSponsors(sponsors.platinum, "Platinum", "#E5E4E2");
                        addSponsors(sponsors.gold, "Gold", "#D4AF37");
                        addSponsors(sponsors.silver, "Silver", "#C0C0C0");
                        addSponsors(sponsors.bronze, "Bronze", "#CD7F32");
                    }
                } catch (e) {
                    error = "Failed to parse sponsors JSON.";
                }
            } else {
                error = "Failed to fetch sponsors.";
            }

            addDefaultApps();
            loading = false;
        };
        xhr.send();
    }


    Component.onCompleted: {
        // FIXME: show keychain/cred dialog.
        apps.init();
    }

    Connections {
        target: apps
        function onStateChanged() {
            var s = apps.state;
            if (!s) return;
            if (s.error) error = s.error;
            email = s.email || "";
            if (s.init) fetchSponsors();
        }

        function onSearch_ready(searchTerm, success, res) {  
            if (!success) {
                console.error("Search failed for term:", searchTerm);
                searchError = true;
                return;
            }
            searchResultsModel.clear();
            const parsedRes = JSON.parse(res);

            if (!parsedRes || !parsedRes.results || !Array.isArray(parsedRes.results)) {
                console.error("Invalid search results format: 'results' array not found or not an array.", res);
                searchError = true;
                return;
            }
            
            searchError = false;

            for (var i = 0; i < parsedRes.results.length; ++i) {
                const item = parsedRes.results[i];
                searchResultsModel.append({
                    id : item.id || 0,
                    bundleId: item.bundle_id || "",
                    name: item.name || "",
                    price: item.price || 0,
                    description: "",
                    logoUrl: "",
                    useBundleIdForIcon: true,
                    sponsorLabel: "",
                    sponsorColor: ""
                });
            }
        }
    }

    contentItem : ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 16
            spacing: 12

            TextField {
                id: searchField
                Layout.preferredWidth: 240
                enabled: true
                placeholderText: isLoggedIn ? "Search for apps..." : "Sign in to search"
                onTextChanged: {
                    if (!apps) return;
                    searchTerm = searchField.text
                    searchResultsModel.clear();
                    // if (searchTerm.length === 0) return;

                    apps.search(searchTerm)

                }  
            }

            Item { Layout.fillWidth: true }

            Label {
                text: isLoggedIn ? ("Signed in as " + email) : "Not signed in"
                color: "#666"
            }

            Button {
                text: isLoggedIn ? "Sign Out" : "Sign In"
                // enabled: 
                onClicked : {
                    const comp = Qt.createComponent("qrc:/src/qml/LoginDialog.qml")

                    // if (comp.status === Component.ready) { 
                        const win = comp.createObject(root,{
                             apps: root.apps
                        })
                        win.open()
                    // } else {
                    //     console.error("Component failed to load:", comp.errorString())
                    // }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"

            ScrollView {
                anchors.fill: parent
                clip: true

                GridView {
                    id: grid
                    anchors.fill: parent
                    anchors.margins: 16
                    cellWidth: Math.max(250, width / 3)
                    cellHeight: 140
                    model: appModel

                    delegate: Item {
                        width: grid.cellWidth - 12
                        height: grid.cellHeight - 12

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
                        }
                    }
                }
            }

            BusyIndicator {
                anchors.centerIn: parent
                running: loading
                visible: loading
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                text: error
                color: "#c00"
                visible: error.length > 0 && !loading
            }
        }
    }
}
