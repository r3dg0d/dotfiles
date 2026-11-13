import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Galaxy clipboard manager. History comes from clip.py (one watcher, bounded local store).
// Type to search, ↑↓ to move, Enter restores to the clipboard and closes, Delete removes, Esc closes.
ShellRoot {
    id: root
    property bool opened: false
    property var entries: []
    property int sel: 0
    property string query: ""
    property bool paused: false
    property string backend: "own"
    property string watcher: ""
    property int count: 0
    property bool pauseApplies: true
    property bool confirmClear: false
    property string status: ""
    readonly property var current: entries[sel] || null

    function ago(ts) { if (!ts) return ""; const s = Math.max(0, Date.now() / 1000 - ts)
        return s < 60 ? "now" : s < 3600 ? Math.floor(s / 60) + " min" : s < 86400 ? Math.floor(s / 3600) + " h" : Math.floor(s / 86400) + " d" }
    function oneLine(t) { return t.replace(/\s+/g, " ").trim() }
    function load() { lister.command = ["python3", Quickshell.shellPath("clip.py"), "list", "--query", root.query, "--limit", "150"]; lister.running = true }
    function act(args) { if (actor.running) return; actor.command = ["python3", Quickshell.shellPath("clip.py")].concat(args); actor.running = true }
    function open() { root.query = ""; root.sel = 0; root.status = ""; root.confirmClear = false; root.opened = true; root.load() }
    function close() { root.opened = false; root.confirmClear = false }
    function move(d) { if (!root.entries.length) return; root.sel = Math.max(0, Math.min(root.entries.length - 1, root.sel + d)); list.positionViewAtIndex(root.sel, ListView.Contain) }
    function restore() { if (root.current) { restorer.command = ["python3", Quickshell.shellPath("clip.py"), "restore", root.current.id]; restorer.running = true } }
    function remove() { if (root.current) root.act(["delete", root.current.id]) }
    function clearAll() { if (!root.confirmClear) { root.confirmClear = true; root.status = "Press Ctrl+Shift+Delete again to erase all " + root.count + " entries · Esc cancels" }
        else { root.confirmClear = false; root.status = ""; root.act(["clear"]) } }
    function togglePause() { root.act(["pause", "toggle"]) }
    function handleKey(k, mods) {
        const ctrl = mods & Qt.ControlModifier, shift = mods & Qt.ShiftModifier
        if (k === Qt.Key_Escape) { if (root.confirmClear) { root.confirmClear = false; root.status = "" } else root.close() }
        else if (k === Qt.Key_Delete && ctrl && shift) root.clearAll()
        else if (k === Qt.Key_Delete || (ctrl && k === Qt.Key_D)) root.remove()
        else if (ctrl && k === Qt.Key_P) root.togglePause()
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.restore()
        else if (k === Qt.Key_Down) root.move(1)
        else if (k === Qt.Key_Up) root.move(-1)
        else if (k === Qt.Key_PageDown) root.move(8)
        else if (k === Qt.Key_PageUp) root.move(-8)
        else return false
        if (k !== Qt.Key_Delete && root.confirmClear && !(ctrl && shift)) { root.confirmClear = false; root.status = "" }
        return true
    }

    Process { id: lister
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text)
            root.entries = d.entries; root.paused = d.paused; root.backend = d.backend; root.watcher = d.watcher; root.count = d.count; root.pauseApplies = d.pause_applies
            root.sel = Math.max(0, Math.min(root.sel, d.entries.length - 1))
            if (d.watcher === "stopped") root.status = "The clipboard watcher is not running: bash ~/.config/quickshell/galaxy-clip/start.sh --watch-only"
        } catch (e) { root.status = "clip.py did not answer" } } } }
    Process { id: actor; onExited: root.load() }
    Process { id: restorer
        stdout: StdioCollector { onStreamFinished: { let ok = false; try { ok = JSON.parse(text).ok } catch (e) {}
            if (ok) root.close(); else root.status = "Could not restore: is wl-copy installed?" } } }
    Timer { interval: 2000; repeat: true; running: root.opened && !root.query.length; onTriggered: root.load() }

    IpcHandler {
        target: "clip"
        function open(): void { root.open() }
        function close(): void { root.close() }
        function toggle(): void { if (root.opened) root.close(); else root.open() }
        // test hooks
        function type(text: string): void { root.query = text; root.sel = 0; root.load() }
        function press(k: string): void { const m = { Up: Qt.Key_Up, Down: Qt.Key_Down, Return: Qt.Key_Return, Escape: Qt.Key_Escape, Delete: Qt.Key_Delete,
            Clear: Qt.Key_Delete, Pause: Qt.Key_P }
            root.handleKey(m[k] || 0, k === "Clear" ? (Qt.ControlModifier | Qt.ShiftModifier) : k === "Pause" ? Qt.ControlModifier : 0) }
    }

    PanelWindow {
        visible: root.opened
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "galaxy-clip"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle { anchors.fill: parent; color: "#8007060d"; MouseArea { anchors.fill: parent; onClicked: root.close() } }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 860; height: 560; radius: Galaxy.radiusWindow; color: "transparent"
            Nebula { anchors.fill: parent; radius: card.radius; seed: 58; glow: 1.1; hot: true }
            MouseArea { anchors.fill: parent }
            scale: root.opened ? 1 : 0.95
            Behavior on scale { SpringAnimation { spring: 4; damping: 0.3 } }
            Connections { target: root; function onOpenedChanged() { if (root.opened) { field.text = ""; field.forceActiveFocus() } } }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 18; spacing: 10
                RowLayout { Layout.fillWidth: true; spacing: 10
                    Text { text: "✦  C L I P B O A R D"; font.family: Galaxy.font; font.pixelSize: 13; color: Galaxy.lavender }
                    Item { Layout.fillWidth: true }
                    Rectangle { visible: root.paused; implicitWidth: pausedT.implicitWidth + 16; implicitHeight: 22; radius: 11; color: Galaxy.warnBg; border.color: Galaxy.warn
                        Text { id: pausedT; anchors.centerIn: parent; text: "CAPTURE PAUSED"; font.family: Galaxy.font; font.pixelSize: 10; color: Galaxy.warn } }
                    Rectangle { visible: root.backend !== "own"; implicitWidth: beT.implicitWidth + 16; implicitHeight: 22; radius: 11; color: Galaxy.raised; border.color: Galaxy.line
                        Text { id: beT; anchors.centerIn: parent; text: "using " + root.backend; font.family: Galaxy.font; font.pixelSize: 10; color: Galaxy.label } }
                    Text { text: root.count + " kept"; font.family: Galaxy.mono; font.pixelSize: 14; color: Galaxy.ink }
                }
                TextField {
                    id: field
                    Layout.fillWidth: true
                    placeholderText: "search clipboard history…"
                    color: Galaxy.ink; placeholderTextColor: Galaxy.dim; selectionColor: Galaxy.violet
                    font.family: Galaxy.font; font.pixelSize: 15; padding: 11
                    background: Rectangle { radius: Galaxy.radiusControl; color: Galaxy.base; border.color: field.activeFocus ? Galaxy.purple : Galaxy.line }
                    onTextEdited: { root.query = text; root.sel = 0; root.load() }
                    Keys.onPressed: e => { if (root.handleKey(e.key, e.modifiers)) e.accepted = true }
                }
                RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
                    ListView {
                        id: list
                        Layout.preferredWidth: 400; Layout.fillHeight: true; clip: true; spacing: 4
                        model: root.entries
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            id: row
                            required property var modelData; required property int index
                            width: list.width; height: 46; radius: Galaxy.radiusControl
                            color: root.sel === index ? Galaxy.raised : "transparent"
                            border.width: root.sel === index ? 1 : 0; border.color: Galaxy.purple
                            RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10
                                Image { visible: row.modelData.kind === "image" && row.modelData.file.length > 0; Layout.preferredWidth: 34; Layout.preferredHeight: 34
                                    source: visible ? "file://" + row.modelData.file : ""; sourceSize.width: 68; sourceSize.height: 68; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                                Text { Layout.fillWidth: true; elide: Text.ElideRight; maximumLineCount: 1; textFormat: Text.PlainText
                                    font.family: Galaxy.font; font.pixelSize: 13; color: row.modelData.kind === "image" ? Galaxy.lavender : Galaxy.ink
                                    text: root.oneLine(row.modelData.preview) }
                                Text { visible: row.modelData.lines > 1; text: row.modelData.lines + " lines"; font.family: Galaxy.font; font.pixelSize: 10; color: Galaxy.label }
                                Text { text: root.ago(row.modelData.ts); font.family: Galaxy.font; font.pixelSize: 10; color: Galaxy.dim }
                            }
                            MouseArea { anchors.fill: parent; onClicked: { root.sel = row.index; field.forceActiveFocus() } onDoubleClicked: { root.sel = row.index; root.restore() } }
                        }
                        Text { anchors.centerIn: parent; visible: !root.entries.length; font.family: Galaxy.font; font.pixelSize: 13; color: Galaxy.dim
                            text: root.query.length ? "Nothing matches “" + root.query + "”" : "Clipboard history is empty" }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; radius: Galaxy.radiusTile; color: Galaxy.card; border.color: Galaxy.line; clip: true
                        Image { anchors.fill: parent; anchors.margins: 14; visible: !!root.current && root.current.kind === "image" && root.current.file.length > 0
                            source: visible ? "file://" + root.current.file : ""; fillMode: Image.PreserveAspectFit; asynchronous: true; sourceSize.width: 900 }
                        Flickable { anchors.fill: parent; anchors.margins: 14; clip: true; contentHeight: prev.implicitHeight
                            visible: !!root.current && root.current.kind === "text"
                            Text { id: prev; width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
                                font.family: Galaxy.mono; font.pixelSize: 13; color: Galaxy.ink
                                text: root.current && root.current.kind === "text" ? root.current.preview + (root.current.size > root.current.preview.length * 4 ? "\n…" : "") : "" } }
                        Text { anchors.centerIn: parent; visible: !!root.current && root.current.kind === "image" && !root.current.file.length
                            text: "image (no preview from this backend)"; font.family: Galaxy.font; font.pixelSize: 12; color: Galaxy.dim }
                    }
                }
                RowLayout { Layout.fillWidth: true; spacing: 8
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; font.family: Galaxy.font; font.pixelSize: 11
                        color: root.status.length ? Galaxy.warn : Galaxy.dim
                        text: root.status.length ? root.status : "↑↓ move · Enter restore · Delete remove · Ctrl+P pause · Ctrl+Shift+Delete clear all · Esc close" }
                    GalaxyButton { text: root.paused ? "Resume capture" : "Pause capture"; enabled: root.pauseApplies; selected: root.paused
                        hint: root.pauseApplies ? "Nothing is recorded while paused" : "Capture is owned by the external cliphist watcher"
                        onClicked: { root.togglePause(); field.forceActiveFocus() } }
                    GalaxyButton { text: root.confirmClear ? "Really clear?" : "Clear history"; danger: true; onClicked: { root.clearAll(); field.forceActiveFocus() } }
                }
            }
        }
    }
}
