import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property bool opened: false
    property string mode: "grid"          // grid | entries | confirm
    property int sel: 0
    property int entrySel: 0
    property var entries: []
    property var caps: ({})
    property bool dry: false
    property var pending: null            // { id, label, arg }
    property int countdown: 5
    property string status: ""
    property real uptime: 0
    readonly property string ui: "Cellforge"
    readonly property string nf: "JetBrainsMono Nerd Font"

    readonly property var actions: [
        { id: "lock",      label: "Lock",      glyph: "󰌾", key: "L", confirm: false },
        { id: "logout",    label: "Log out",   glyph: "󰍃", key: "O", confirm: true  },
        { id: "suspend",   label: "Suspend",   glyph: "󰒲", key: "S", confirm: false, cap: "CanSuspend" },
        { id: "hibernate", label: "Hibernate", glyph: "󰤄", key: "H", confirm: true,  cap: "CanHibernate" },
        { id: "reboot",    label: "Reboot",    glyph: "󰜉", key: "R", confirm: true  },
        { id: "shutdown",  label: "Shut down", glyph: "󰐥", key: "P", confirm: true  },
        { id: "firmware",  label: "Firmware",  glyph: "󰍛", key: "F", confirm: true,  cap: "CanRebootToFirmwareSetup" },
        { id: "entries",   label: "Boot entry", glyph: "󰑓", key: "B", confirm: false, cap: "CanRebootToBootLoaderEntry" }
    ]
    function available(a) { return !a.cap || caps[a.cap] === "yes" || caps[a.cap] === undefined }
    function fmtUp(s) { s = Math.floor(s); const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return (d ? d + "d " : "") + String(h).padStart(2, "0") + "h " + String(m).padStart(2, "0") + "m" }
    function entryLabel(e) { const m = /nixos-generation-(\d+)/.exec(e); return m ? "NixOS generation " + m[1] : e.replace(/\.conf$/, "").replace(/-/g, " ") }

    function open() { mode = "grid"; status = ""; pending = null; opened = true; capsProc.running = true; entriesProc.running = true; dryFile.reload(); upFile.reload() }
    function close() { countdownTimer.stop(); opened = false }
    function activate(a) {
        if (!available(a)) return
        if (a.id === "entries") { mode = "entries"; entrySel = 0; return }
        if (a.confirm) { pending = { id: a.id, label: a.label, glyph: a.glyph }; countdown = 5; mode = "confirm"; countdownTimer.restart() }
        else run(a.id, "")
    }
    function pickEntry(i) {
        const e = entries[i]; if (!e) return
        pending = { id: "entry", arg: e, label: "Reboot into " + entryLabel(e), glyph: "󰑓" }; countdown = 5; mode = "confirm"; countdownTimer.restart()
    }
    function handleKey(k, txt) {
                if (root.mode === "confirm") {
                    if (k === Qt.Key_Escape || k === Qt.Key_Backspace) root.cancel()
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.run(root.pending.id, root.pending.arg || "")
                } else if (root.mode === "entries") {
                    if (k === Qt.Key_Escape || k === Qt.Key_Backspace || k === Qt.Key_Left) root.mode = "grid"
                    else if (k === Qt.Key_Down) root.entrySel = Math.min(root.entries.length - 1, root.entrySel + 1)
                    else if (k === Qt.Key_Up) root.entrySel = Math.max(0, root.entrySel - 1)
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.pickEntry(root.entrySel)
                } else {
                    if (k === Qt.Key_Escape) root.close()
                    else if (k === Qt.Key_Right) root.sel = (root.sel + 1) % 8
                    else if (k === Qt.Key_Left) root.sel = (root.sel + 7) % 8
                    else if (k === Qt.Key_Down || k === Qt.Key_Up) root.sel = (root.sel + 4) % 8
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.activate(root.actions[root.sel])
                    else { const ch = txt.toUpperCase(); const i = root.actions.findIndex(a => a.key === ch); if (i >= 0) { root.sel = i; root.activate(root.actions[i]) } }
                }
    }
    function cancel() { countdownTimer.stop(); pending = null; mode = "grid"; status = "Cancelled" }
    function run(id, arg) {
        countdownTimer.stop()
        runner.command = ["bash", Quickshell.shellPath("power.sh"), id].concat(arg ? [arg] : [])
        runner.running = true
        if (!dry) opened = false
    }

    Timer { id: countdownTimer; interval: 1000; repeat: true
        onTriggered: { root.countdown--; if (root.countdown <= 0) root.run(root.pending.id, root.pending.arg || "") } }
    Timer { interval: 30000; repeat: true; running: root.opened; onTriggered: upFile.reload() }
    FileView { id: upFile; path: "/proc/uptime"; onLoaded: root.uptime = parseFloat(text().split(" ")[0]) || 0 }
    FileView { id: dryFile; path: Quickshell.env("HOME") + "/.cache/galaxy-power.dry"; printErrors: false
        onLoaded: root.dry = true; onLoadFailed: root.dry = Quickshell.env("GALAXY_POWER_DRY") === "1" }
    Process { id: capsProc; command: ["bash", Quickshell.shellPath("power.sh"), "caps"]
        stdout: StdioCollector { onStreamFinished: { const c = {}; text.trim().split("\n").forEach(l => { const p = l.split("="); if (p.length === 2) c[p[0]] = p[1] }); root.caps = c } } }
    Process { id: entriesProc; command: ["bash", Quickshell.shellPath("power.sh"), "entries"]
        stdout: StdioCollector { onStreamFinished: { try { root.entries = JSON.parse(text).data.filter(e => e.indexOf("auto-") !== 0) } catch (e) { root.entries = [] } } } }
    Process { id: runner; stdout: StdioCollector { onStreamFinished: { if (text.trim()) root.status = text.trim().replace(/^.*DRY-RUN: /, "dry run → ") } }
        onExited: if (root.dry) root.mode = "grid" }

    IpcHandler {
        target: "power"
        function open(): void { root.open() }
        function close(): void { root.close() }
        function toggle(): void { if (root.opened) root.close(); else root.open() }
        function select(i: int): void { root.sel = i }
        // test hook: simulate a key (Left/Right/Up/Down/Return/Escape or a letter)
        function press(k: string): void { const m = { Left: Qt.Key_Left, Right: Qt.Key_Right, Up: Qt.Key_Up, Down: Qt.Key_Down, Return: Qt.Key_Return, Escape: Qt.Key_Escape }; root.handleKey(m[k] || 0, m[k] ? "" : k) }
    }

    PanelWindow {
        id: win
        visible: root.opened
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "galaxy-power"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle { anchors.fill: parent; color: "#b007060d"
            MouseArea { anchors.fill: parent; onClicked: root.mode === "confirm" ? root.cancel() : root.close() } }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 760; height: col.implicitHeight + 56; radius: 26
            color: "transparent"
            Nebula { anchors.fill: parent; radius: card.radius; seed: 23; glow: 1.2; hot: true }
            MouseArea { anchors.fill: parent }   // swallow clicks
            scale: root.opened ? 1 : 0.94
            Behavior on scale { SpringAnimation { spring: 4; damping: 0.3 } }

            focus: true
            Keys.onPressed: e => { root.handleKey(e.key, e.text || ""); e.accepted = true }
            Connections { target: root; function onOpenedChanged() { if (root.opened) card.forceActiveFocus() } }

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 28 }
                spacing: 20
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    Text { text: "✦  P O W E R"; font.family: root.ui; font.pixelSize: 13; color: "#d4b8ff"; Layout.fillWidth: true }
                    Rectangle { visible: root.dry; implicitWidth: dryT.implicitWidth + 16; implicitHeight: 22; radius: 11; color: "#3a2d12"; border.color: "#ffd479"
                        Text { id: dryT; anchors.centerIn: parent; text: "DRY RUN"; font.family: root.ui; font.pixelSize: 10; color: "#ffd479" } }
                    Text { text: "UP"; font.family: root.ui; font.pixelSize: 10; color: "#8a84a8" }
                    Text { text: root.fmtUp(root.uptime); font.family: "Zerodot"; font.pixelSize: 18; color: "#f2f0ff" }
                }

                // ---- grid ----
                GridLayout {
                    visible: root.mode === "grid"
                    Layout.fillWidth: true; columns: 4; columnSpacing: 14; rowSpacing: 14
                    Repeater {
                        model: root.actions
                        Rectangle {
                            id: tile
                            required property var modelData; required property int index
                            readonly property bool on: root.sel === index
                            readonly property bool ok: root.available(modelData)
                            readonly property bool danger: modelData.id === "shutdown" || modelData.id === "reboot"
                            Layout.fillWidth: true; implicitHeight: 128; radius: 20
                            opacity: ok ? 1 : 0.35
                            color: on ? (danger ? "#2a1230" : "#22183f") : "#110d20"
                            border.color: on ? (danger ? "#ff8fb1" : "#b46bff") : "#2a2344"; border.width: on ? 2 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Column {
                                anchors.centerIn: parent; spacing: 10
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.glyph; font.family: root.nf; font.pixelSize: 40
                                    color: tile.on ? (tile.danger ? "#ff8fb1" : "#d4b8ff") : "#9a8fc4" }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.label; font.family: root.ui; font.pixelSize: 13; color: "#f2f0ff" }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.key; font.family: "Zerodot"; font.pixelSize: 10; color: "#5d5878" }
                            }
                            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onEntered: root.sel = tile.index; onClicked: root.activate(tile.modelData) }
                        }
                    }
                }

                // ---- boot entries ----
                ColumnLayout {
                    visible: root.mode === "entries"; Layout.fillWidth: true; spacing: 6
                    Text { text: "Reboot into…  (systemd-boot, one-time)"; font.family: root.ui; font.pixelSize: 12; color: "#9a96b3" }
                    Repeater {
                        model: root.entries
                        Rectangle {
                            required property var modelData; required property int index
                            Layout.fillWidth: true; implicitHeight: 34; radius: 10
                            color: root.entrySel === index ? "#22183f" : "transparent"; border.color: root.entrySel === index ? "#b46bff" : "#1d1833"
                            RowLayout { anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                                Text { text: "󰑓"; font.family: root.nf; color: "#b46bff"; font.pixelSize: 14 }
                                Text { Layout.fillWidth: true; text: root.entryLabel(modelData) + (index === 0 ? "   · newest" : ""); font.family: root.ui; font.pixelSize: 12; color: "#f2f0ff" }
                                Text { text: modelData; font.family: root.ui; font.pixelSize: 9; color: "#5d5878" } }
                            MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: root.entrySel = index; onClicked: root.pickEntry(index) }
                        }
                    }
                    Text { visible: root.entries.length === 0; text: "No boot entries reported by logind."; font.family: root.ui; color: "#ffd479"; font.pixelSize: 12 }
                }

                // ---- confirm ----
                ColumnLayout {
                    visible: root.mode === "confirm"; Layout.fillWidth: true; spacing: 16
                    Item { Layout.fillWidth: true; implicitHeight: 150
                        Canvas {
                            id: ring; anchors.centerIn: parent; width: 140; height: 140
                            property real frac: root.countdown / 5
                            onFracChanged: requestPaint()
                            onPaint: { const c = getContext("2d"); c.reset(); c.lineWidth = 6
                                c.strokeStyle = "#2a2344"; c.beginPath(); c.arc(70, 70, 62, 0, 2 * Math.PI); c.stroke()
                                c.strokeStyle = "#ff8fb1"; c.beginPath(); c.arc(70, 70, 62, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * frac); c.stroke() }
                            Text { anchors.centerIn: parent; text: root.countdown; font.family: "Zerodot"; font.pixelSize: 54; color: "#f2f0ff" }
                        }
                    }
                    Text { Layout.alignment: Qt.AlignHCenter; text: root.pending ? (root.pending.glyph + "  " + root.pending.label + " in " + root.countdown + "s") : ""
                        font.family: root.ui; font.pixelSize: 16; color: "#ff8fb1" }
                    RowLayout { Layout.alignment: Qt.AlignHCenter; spacing: 12
                        Rectangle { implicitWidth: 170; implicitHeight: 40; radius: 12; color: "#22183f"; border.color: "#b46bff"
                            Text { anchors.centerIn: parent; text: "Cancel  ·  Esc"; font.family: root.ui; color: "#f2f0ff"; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.cancel() } }
                        Rectangle { implicitWidth: 170; implicitHeight: 40; radius: 12; color: "#2a1230"; border.color: "#ff8fb1"
                            Text { anchors.centerIn: parent; text: "Now  ·  Enter"; font.family: root.ui; color: "#ff8fb1"; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.run(root.pending.id, root.pending.arg || "") } }
                    }
                }

                Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.family: root.ui; font.pixelSize: 10; color: "#5d5878"
                    text: root.status ? root.status : root.mode === "grid" ? "←→↑↓ move · Enter select · letter shortcut · Esc close"
                        : root.mode === "entries" ? "↑↓ move · Enter reboot into · Esc back" : "Esc cancel · Enter run now" }
            }
        }
    }
}
