pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Frontend state for Storage Optimizer. The scanner and every cleanup live in
// storage-optimizer-helper; QML never walks the disk. Idle cost: a watched
// cache file plus one `summary` call (a statvfs, ~15 ms) every 10 minutes
// while the widget is running — never a scan.
Singleton {
    id: root

    readonly property string helper: Quickshell.env("STORAGE_OPTIMIZER_HELPER") || "storage-optimizer-helper"
    readonly property string launcher: Quickshell.env("STORAGE_OPTIMIZER_LAUNCHER") || "storage-optimizer"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/storage-optimizer"

    property var summary: ({})
    property var scan: ({})
    property bool hasScan: !!scan.scanId

    // scan progress
    property bool scanning: scanProc.running
    property var progress: ({})
    property string scanMessage: ""
    property bool scanOk: true

    // cleanup
    property bool cleaning: cleanProc.running
    property string cleanPhase: ""
    property var cleanSteps: ({})
    property var cleanResult: null
    signal cleanLog(string line)
    // "" | "waiting" | "granted" | "failed" — polkit authentication for the
    // root categories (Nix generations/garbage, journal).
    property string authState: ""
    property string authMessage: ""
    property real cleanStartedAt: 0
    property int cleanDurationMs: 0
    property string cleanDurationText: ""

    // What the helper is doing right now, in *any* process (the app or the
    // widget): written by storage-optimizer-helper on phase changes only.
    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/storage-optimizer"
    property var activity: ({})
    readonly property string busyKind: activity.activity || (cleaning ? "cleaning" : scanning ? "scanning" : "")
    readonly property string busyPhase: activity.phase || (cleaning ? cleanPhase : scanning ? "Analyzing storage…" : "")
    FileView {
        id: activityFile
        path: root.runtimeDir + "/activity.json"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.activity = JSON.parse(text()); } catch (e) { root.activity = ({}); } }
    }

    property string actionMessage: ""
    property bool actionOk: true
    property var preview: ({})

    readonly property var home: summary.home || ({})
    readonly property var lastScan: summary.lastScan || null

    FileView {
        path: root.cacheDir + "/scan.json"
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: { try { root.scan = JSON.parse(text()); } catch (e) {} root.refreshSummary(); }
    }

    Process {
        id: summaryProc
        command: [root.helper, "summary"]
        stdout: StdioCollector { onStreamFinished: { try { root.summary = JSON.parse(text); } catch (e) {} } }
        // `summary` also creates/clears the activity file; pick it up.
        onExited: activityFile.reload()
    }
    Timer {
        // Free space only; cheap. No scanning ever happens on a timer.
        interval: 10 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refreshSummary()
    }

    Process {
        id: scanProc
        command: [root.helper, "scan"]
        stdout: SplitParser {
            onRead: data => {
                let ev; try { ev = JSON.parse(data); } catch (e) { return; }
                if (ev.event === "progress") root.progress = ev;
                else if (ev.event === "result") { root.scanMessage = ev.message || ""; root.scanOk = !!ev.ok; }
            }
        }
        onExited: root.refreshSummary()
    }

    Process {
        id: cleanProc
        stdout: SplitParser {
            onRead: data => {
                let ev; try { ev = JSON.parse(data); } catch (e) { root.cleanLog(data); return; }
                switch (ev.event) {
                case "log": root.cleanLog(ev.line); break;
                case "phase": root.cleanPhase = ev.text; break;
                case "progress": root.cleanPhase = "Rescanning… " + (ev.area || ""); break;
                case "step": {
                    const s = Object.assign({}, root.cleanSteps); s[ev.id] = ev.status; root.cleanSteps = s; break;
                }
                case "auth":
                    root.authState = ev.state;
                    root.authMessage = ev.message || "";
                    if (ev.state === "waiting") root.cleanPhase = "Waiting for authentication…";
                    else if (ev.state === "granted") root.cleanPhase = "Cleaning system data…";
                    break;
                case "result":
                    root.cleanResult = ev;
                    root.cleanPhase = ev.ok ? "Finished" : "Finished with errors";
                    root.cleanDurationMs = ev.durationMs || (root.cleanStartedAt ? (Date.now() - root.cleanStartedAt) : 0);
                    root.cleanDurationText = ev.duration || root.formatDuration(root.cleanDurationMs);
                    break;
                default: break;
                }
            }
        }
        onExited: (code) => {
            if (!root.cleanResult) root.cleanResult = { ok: false, message: "Cleanup backend exited (code " + code + ")" };
            root.refreshSummary();
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { const r = JSON.parse(text); root.actionMessage = r.message || (r.ok ? "Done" : "Failed"); root.actionOk = !!r.ok; }
                catch (e) { root.actionMessage = text; root.actionOk = false; }
            }
        }
    }
    Process {
        id: previewProc
        property string cat: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const p = Object.assign({}, root.preview);
                try { p[previewProc.cat] = JSON.parse(text); } catch (e) { p[previewProc.cat] = { error: text }; }
                root.preview = p;
            }
        }
    }

    function refreshSummary() { if (!summaryProc.running) summaryProc.running = true; }
    function startScan() {
        if (scanProc.running || cleanProc.running) return;
        progress = ({}); scanMessage = ""; scanOk = true;
        scanProc.running = true;
    }
    function cancelScan() { if (scanProc.running) scanProc.signal(15); }

    // Returns false (with the reason in cleanResult) when it cannot start, so
    // the UI never shows an empty "cleaning" view.
    function startClean(categories) {
        const blocked = cleanProc.running ? "A cleanup is already running."
                      : (scanProc.running || busyKind === "scanning") ? "A scan is running — wait for it to finish, then confirm again."
                      : !scan.scanId ? "Analyze first — there is no scan to clean from."
                      : categories.length === 0 ? "No categories selected." : "";
        if (blocked !== "") {
            cleanSteps = ({}); authState = ""; authMessage = ""; cleanPhase = "";
            cleanResult = { ok: false, message: blocked };
            return false;
        }
        cleanSteps = ({}); cleanResult = null; cleanPhase = "Starting…"; authState = ""; authMessage = "";
        cleanStartedAt = Date.now(); cleanDurationMs = 0; cleanDurationText = "";
        cleanProc.command = [helper, "clean", "--scan", scan.scanId, "--categories", categories.join(",")];
        cleanProc.running = true;
        return true;
    }
    function trash(path) {
        actionMessage = ""; actionProc.command = [helper, "trash", path]; actionProc.running = true;
    }
    function setIgnored(path, ignore) {
        actionMessage = ""; actionProc.command = [helper, ignore ? "ignore" : "unignore", path]; actionProc.running = true;
    }
    function loadPreview(cat) {
        if (previewProc.running) return;
        previewProc.cat = cat; previewProc.command = [helper, "preview", cat]; previewProc.running = true;
    }
    function openApp(page) { Quickshell.execDetached([launcher].concat(page ? [page] : [])); }
    function openPath(p) { Quickshell.execDetached(["xdg-open", p]); }
    function openFolder(p) {
        // Show the item selected in the file manager when it supports it.
        Quickshell.execDetached(["dbus-send", "--session", "--dest=org.freedesktop.FileManager1", "--type=method_call",
                                 "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1.ShowItems",
                                 "array:string:file://" + encodeURI(p), "string:"]);
    }

    function formatDuration(ms) {
        if (!ms || ms < 0) return "";
        if (ms < 1000) return ms + "ms";
        const s = Math.floor(ms / 1000);
        if (s < 60) return s + "s";
        const m = Math.floor(s / 60), rem = s % 60;
        if (m < 60) return m + "m " + rem + "s";
        return Math.floor(m / 60) + "h " + (m % 60) + "m " + rem + "s";
    }

    Timer {
        interval: 1000
        running: root.cleaning && root.cleanStartedAt > 0
        repeat: true
        onTriggered: {
            root.cleanDurationMs = Date.now() - root.cleanStartedAt;
            root.cleanDurationText = root.formatDuration(root.cleanDurationMs);
        }
    }

    Component.onCompleted: refreshSummary()
}
