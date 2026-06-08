pragma Singleton

import QtQuick

QtObject {
    id: root
    property var size_units : ["B","KB","MB","GB","TB"]

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


    function formatSize(_size) {
        let unit_index = 0;

        let size = _size;

        while(size >= 1024 && unit_index < 4) {
            size /= 1024;
            unit_index++;
        }

        return `${size.toFixed(2)} ${root.size_units[unit_index]}`;
    }
}