pragma Singleton

import QtQuick

QtObject {
    id: root
    property var size_units : ["B","KB","MB","GB","TB"]

    function fetchAppIconFromApple(bundleId, cb) {
        if (!bundleId) { cb(""); return; }
        fetch_app(bundleId, function(app, error) {
            if (error || !app) { cb(""); return; }
            cb(app.artworkUrl100 || app.artworkUrl512 || app.artworkUrl60 || "");
        });
    }

    function fetch_app_name(bundleId,cb) {
        if (!bundleId) { cb(""); return; }
        fetch_app(bundleId, function(app, error) {
            if (error || !app) { cb(""); return; }
            cb(app.trackName || "");
        });
    }

    function fetch_app(bundleId, cb) {
        if (!bundleId) {
            cb(null, "Missing bundle id");
            return;
        }

        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://itunes.apple.com/lookup?bundleId=" + encodeURIComponent(bundleId));
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;

            if (xhr.status !== 200) {
                cb(null, "Failed to fetch app details.");
                return;
            }

            try {
                var obj = JSON.parse(xhr.responseText);
                var results = obj && obj.results ? obj.results : [];
                if (!results.length) {
                    cb(null, "No App Store details found for this bundle id.");
                    return;
                }
                cb(results[0], "");
            } catch (e) {
                cb(null, "Failed to parse App Store details.");
            }
        };
        xhr.send();
    }

    function is_video_file(name) {
        var lower = (name || "").toLowerCase()
        return lower.endsWith(".mp4") || lower.endsWith(".m4v") || lower.endsWith(".mov") ||
               lower.endsWith(".avi") || lower.endsWith(".mkv")
    }

    function is_image_file(name) {
        var lower = (name || "").toLowerCase()
        return lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
               lower.endsWith(".heic") || lower.endsWith(".heif") || lower.endsWith(".gif") ||
               lower.endsWith(".bmp") || lower.endsWith(".webp") || lower.endsWith(".tif") ||
               lower.endsWith(".tiff")
    }

    function is_previewable(name) {
        return is_video_file(name) || is_image_file(name)
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

    // single-shot connection helper
    // since this does not exist in QML
    function connectOnce(signal, handler) {
        var wrapper = function() {
            handler.apply(this, arguments)
            signal.disconnect(wrapper)
        }
        signal.connect(wrapper)
    }


    function setTimeout(callback, delay) {
        var timer = Qt.createQmlObject(
            "import QtQuick; Timer { interval: " + delay + "; repeat: false; running: true; }",
            root,
            "dynamicTimer"
        );

        timer.triggered.connect(function() {
            callback();
            timer.destroy(); // Clean up memory after execution
        });
    }

    function messageBox(parent, title, message, buttons, onButtonClicked) {
        var dialog = Qt.createQmlObject(
            "import QtQuick; import QtQuick.Dialogs; MessageDialog { buttons: MessageDialog.Ok }",
            parent || root,
            "dynamicMessageBox"
        );

        dialog.title = title;
        dialog.text = message;
        if (buttons !== undefined)
            dialog.buttons = buttons;
        dialog.buttonClicked.connect(function(button, role) {
            if (onButtonClicked)
                onButtonClicked(button, role);
            dialog.destroy();
        });
        dialog.open();
        return dialog;
    }

    function showError(parent, message) {
        return messageBox(parent, qsTr("Error"), message);
    }

    function showWarning(parent, message) {
        return messageBox(parent, qsTr("Warning"), message);
    }

    function showInfo(parent, message) {
        return messageBox(parent, qsTr("Information"), message);
    }


    function toFileUrl(path) {
        if (Qt.platform.os === "windows")
            return "file:///" + path.replace(/\\/g, "/")
        return "file://" + path
    }
}
