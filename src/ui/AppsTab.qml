import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt5Compat.GraphicalEffects
import QtQuick.Controls.impl 

Item {
    id: root
    anchors.fill: parent

    // readonly property Apps apps
    readonly property string sponsorsUrl: "https://raw.githubusercontent.com/iDescriptor/iDescriptor/refs/heads/main/sponsors.json"

    property bool loading: true
    property string error: ""
    property string email: ""
    property bool isLoggedIn: email.length > 0

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

    function fetchAppIconFromApple(bundleId, cb) {
        if (!bundleId) { cb(""); return; }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://itunes.apple.com/lookup?bundleId=" + encodeURIComponent(bundleId));
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) { cb(""); return; }
            try {
                var obj = JSON.parse(xhr.responseText);
                var results = obj && obj.results ? obj.results : [];
                var iconUrl = results.length ? (results[0].artworkUrl100 || "") : "";
                cb(iconUrl);
            } catch (e) {
                cb("");
            }
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
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 16
            spacing: 12

            TextField {
                Layout.preferredWidth: 240
                enabled: true
                placeholderText: isLoggedIn ? "Search for apps..." : "Sign in to search"
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
                    width: parent.width
                    height: parent.height
                    cellWidth: Math.max(250, parent.width / 3)
                    cellHeight: 140
                    model: appModel
                    interactive: true

                    delegate: Rectangle {
                        id : rec
                        width: grid.cellWidth - 20
                        height: grid.cellHeight - 20
                        radius: 8
                        border.color: "#ddd"
                        color: "transparent"

                        property string iconSource: ""

                        Component.onCompleted: {
                            if (model.logoUrl && !model.useBundleIdForIcon) {
                                iconSource = model.logoUrl;
                            } else if (model.bundleId) {
                                fetchAppIconFromApple(model.bundleId, function(url) { iconSource = url; });
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            IconLoader {
                                iconSource: rec.iconSource
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Label {
                                        text: model.name
                                        font.pixelSize: 16
                                        wrapMode: Text.WordWrap
                                    }

                                    Rectangle {
                                        visible: model.sponsorLabel && model.sponsorLabel.length > 0
                                        color: model.sponsorColor
                                        radius: 4
                                        height: 16

                                        Label {
                                            anchors.centerIn: parent
                                            text: model.sponsorLabel
                                            font.pixelSize: 10
                                            color: "#333"
                                            padding: 4
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                Label {
                                    text: model.description
                                    color: "#666"
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }
                            }

                            ColumnLayout {
                                spacing: 6
                                // FIXME: wire up click handling 
                                Button {
                                    text: "Install"
                                    // color: "#007AFF"
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                Button {
                                    text: (model.websiteUrl && model.websiteUrl.length) ? "Website" : "Download IPA"
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }
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
