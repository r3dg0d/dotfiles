import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: app
    property var st: ({ vms: [], checks: {}, docker: false })
    property string updated: ""
    property string toastText: ""
    function refresh() { if (!stateProc.running) stateProc.running = true }
    function act(kind, verb, name) { run(["act", kind, verb, name]); toast(verb + " " + name + "…"); refreshSoon.restart() }
    function term(cmd) { run(["term", cmd]) }
    function run(args) { const p = runner.createObject(app, { command: ["python3", Quickshell.shellPath("vm.py")].concat(args) }); p.running = true }
    function toast(t) { toastText = t; toastTimer.restart() }
    function openKind(k) { const w = ({ android: wAndroid, windows: wWindows, linux: wLinux, ios: wIos, macos: wMacos, all: wAll })[k]; if (w) { w.opened = true; refresh() } }
    Component { id: runner; Process { onExited: destroy() } }
    Timer { id: toastTimer; interval: 7000; onTriggered: app.toastText = "" }
    Timer { id: refreshSoon; interval: 2500; onTriggered: app.refresh() }
    Timer { interval: 5000; repeat: true; triggeredOnStart: true; running: wAll.opened || wAndroid.opened || wWindows.opened || wLinux.opened; onTriggered: app.refresh() }
    Process {
        id: stateProc; command: ["python3", Quickshell.shellPath("vm.py"), "state"]
        stdout: StdioCollector { onStreamFinished: { try { app.st = JSON.parse(text); app.updated = Qt.formatTime(new Date(), "h:mm:ss AP") } catch (e) {} } }
    }
    IpcHandler {
        target: "vm"
        function open(kind: string): void { app.openKind(kind) }
        function close(kind: string): void { const w = ({ android: wAndroid, windows: wWindows, linux: wLinux, ios: wIos, macos: wMacos, all: wAll })[kind]; if (w) w.opened = false }
        function toggle(kind: string): void { const w = ({ android: wAndroid, windows: wWindows, linux: wLinux, ios: wIos, macos: wMacos, all: wAll })[kind]; if (w) { if (w.opened) w.opened = false; else app.openKind(kind) } }
    }
    VmPanel { id: wAll; kind: "all"; app: app }
    VmPanel { id: wAndroid; kind: "android"; app: app }
    VmPanel { id: wWindows; kind: "windows"; app: app }
    VmPanel { id: wLinux; kind: "linux"; app: app }
    VmPanel { id: wIos; kind: "ios"; app: app }
    VmPanel { id: wMacos; kind: "macos"; app: app }
}
