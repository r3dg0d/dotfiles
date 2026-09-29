pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Frontend state for NixOS Updater. All logic lives in nixos-updater-helper;
// this only runs it and turns its JSON into properties. Idle cost is one
// watched file (the status cache) — no timers, no polling.
Singleton {
    id: root

    readonly property string helper: Quickshell.env("NIXOS_UPDATER_HELPER") || "nixos-updater-helper"
    readonly property string launcher: Quickshell.env("NIXOS_UPDATER_LAUNCHER") || "nixos-updater"
    readonly property string cachePath: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/nixos-updater/status.json"

    property var status: ({})
    property bool loaded: false
    property bool checking: refreshProc.running
    property string checkError: ""
    property var plan: null

    // --- apply run state
    property bool running: applyProc.running
    property string runAction: ""
    property string phase: ""
    property bool cancellable: false
    property bool cancelRequested: false
    property var steps: ({})
    property var result: null
    property string logPath: ""
    // "" | "waiting" | "granted" | "failed" — polkit password prompt state.
    property string authState: ""
    property string authMessage: ""
    // Elapsed time for the active/last apply (honest wall clock; not a fake %).
    property real runStartedAt: 0
    property int durationMs: 0
    property string durationText: ""
    signal logLine(string line)
    signal runStarted()

    readonly property var summary: status.summary || ({})
    readonly property string state: checking ? "checking" : (summary.state || "unknown")
    readonly property int updateCount: summary.updateCount || 0

    FileView {
        id: cache
        path: root.cachePath
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: {
            try { root.status = JSON.parse(text()); root.loaded = true; } catch (e) {}
        }
    }

    // Local facts only (generation, kernel, reboot state); no network.
    Process {
        id: localProc
        command: [root.helper, "status"]
        stdout: StdioCollector {}
    }
    Process {
        id: refreshProc
        command: [root.helper, "status", "--refresh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.status = JSON.parse(text); root.checkError = ""; }
                catch (e) { root.checkError = "Check failed: backend returned no data"; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") root.checkError = text.trim().split("\n").pop() }
    }
    Process {
        id: planProc
        command: [root.helper, "plan"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.plan = JSON.parse(text); } catch (e) { root.plan = null; } }
        }
    }
    Process {
        id: cancelProc
        command: [root.helper, "cancel"]
    }
    Process {
        id: applyProc
        stdout: SplitParser {
            onRead: data => root.handleEvent(data)
        }
        onExited: (code, st) => {
            if (!root.result)
                root.result = { ok: false, message: "The updater backend exited unexpectedly (code " + code + ")." };
            root.cancellable = false;
            localProc.running = true;
        }
    }

    function refreshLocal() { if (!localProc.running) localProc.running = true; }
    function check() { if (!refreshProc.running && !applyProc.running) refreshProc.running = true; }
    function loadPlan() { plan = null; planProc.running = true; }

    function handleEvent(line) {
        let ev;
        try { ev = JSON.parse(line); } catch (e) { logLine(line); return; }
        switch (ev.event) {
        case "start": logPath = ev.log || ""; break;
        case "log": logLine(ev.line); break;
        case "phase": phase = ev.text; cancellable = !!ev.cancellable; break;
        case "step": {
            const s = Object.assign({}, steps);
            s[ev.id] = Object.assign({}, s[ev.id] || {}, { status: ev.status, title: ev.title || (s[ev.id] || {}).title });
            steps = s;
            break;
        }
        case "auth":
            authState = ev.state;
            authMessage = ev.message || "";
            if (ev.state === "waiting") { phase = "Waiting for authentication…"; cancellable = false; }
            break;
        case "diff": logLine("flake.lock changes: " + JSON.stringify(ev.changes)); break;
        case "result":
            result = ev;
            phase = ev.ok ? "Finished" : "Failed";
            durationMs = ev.durationMs || (runStartedAt ? (Date.now() - runStartedAt) : 0);
            durationText = ev.duration || formatDuration(durationMs);
            break;
        default: break;
        }
    }

    // args: e.g. ["update-all", "--steps", "flatpak-user,nixpkgs,rebuild", "--release", "…"]
    function apply(args) {
        if (applyProc.running) return;
        runAction = args[0];
        steps = ({});
        result = null;
        phase = "Starting…";
        cancellable = true;
        cancelRequested = false;
        logPath = "";
        authState = "";
        authMessage = "";
        runStartedAt = Date.now();
        durationMs = 0;
        durationText = "";
        applyProc.command = [helper, "apply"].concat(args);
        applyProc.running = true;
        runStarted();
    }
    function cancel() {
        if (!applyProc.running || cancelRequested) return;
        cancelRequested = true;
        cancelProc.running = true;
    }

    function openApp(page) {
        Quickshell.execDetached([launcher].concat(page ? [page] : []));
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

    // Live elapsed display while an apply is running (1 Hz; no fake progress %).
    Timer {
        interval: 1000
        running: root.running && root.runStartedAt > 0
        repeat: true
        onTriggered: {
            root.durationMs = Date.now() - root.runStartedAt;
            root.durationText = root.formatDuration(root.durationMs);
        }
    }

    Component.onCompleted: refreshLocal()
}
