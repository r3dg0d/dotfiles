import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Galaxy emoji picker. Search Unicode names and keywords, arrows to move, Enter copies the exact
// sequence to the Wayland clipboard and closes, Esc closes. Artwork: Twemoji (see ATTRIBUTION.md).
ShellRoot {
    id: root
    property bool opened: false
    property var all: []                 // rows from emoji.json: {e, n, g, k, a, s}
    property var groups: []
    property var results: []
    property var recents: []
    property string query: ""
    property int group: -1               // -1 all, -2 recents, else Unicode group number
    property int tone: 0                 // 0 default, 1..5 Fitzpatrick
    property int sel: 0
    property bool variants: false        // showing the skin-tone variants of one emoji
    property var variantOf: null
    property string assets: ""
    property bool assetsReady: false
    property bool fetching: false
    property string status: ""
    property bool autoTab: false         // open on Recent once the backend has answered, if there are any
    readonly property int columns: 10
    readonly property var tabs: [-1, -2, 0, 1, 3, 4, 5, 6, 7, 8, 9]
    readonly property var tabLabels: ({ "-1": "All", "-2": "Recent" })

    // Code points of the whole sequence. Walks UTF-16 by hand: the QML engine's Array.from() yields
    // surrogate halves for astral characters, which would corrupt every emoji above U+FFFF.
    function hex(e) {
        const out = []
        for (let i = 0; i < e.length; i++) {
            const cp = e.codePointAt(i)
            out.push(cp.toString(16))
            if (cp > 0xffff) i++
        }
        return out.join("-")
    }
    function art(row) { return root.assetsReady && row.a ? "file://" + root.assets + "/" + row.a + ".svg" : "" }
    // The row to show for a base emoji at the chosen tone (single-tone variants only).
    function toned(row) {
        if (root.tone === 0 || !row.s) return row
        const v = row.s.find(s => s.t.length === 1 && s.t[0] === root.tone)
        return v ? { e: v.e, n: v.n, a: v.a, g: row.g, k: row.k, s: row.s } : row
    }
    function score(row, words) {
        let total = 0
        for (const w of words) {
            let best = 0
            const name = row.n.toLowerCase()
            if (name === w) best = 100
            else if (name.startsWith(w)) best = 80
            else if (name.split(/[\s:,-]+/).some(p => p.startsWith(w))) best = 60
            else if (row.k.some(k => k === w)) best = 70
            else if (row.k.some(k => k.startsWith(w))) best = 40
            else if (name.indexOf(w) >= 0) best = 25
            else if (row.k.some(k => k.indexOf(w) >= 0)) best = 15
            if (best === 0) return 0
            total += best
        }
        return total
    }
    function refresh() {
        const words = root.query.toLowerCase().trim().split(/\s+/).filter(w => w.length)
        let rows
        if (root.variants && root.variantOf) {
            rows = [root.variantOf].concat(root.variantOf.s.map(s => ({ e: s.e, n: s.n, a: s.a, g: root.variantOf.g, k: [] })))
        } else if (words.length) {
            rows = root.all.map(r => ({ r: r, s: root.score(r, words) })).filter(x => x.s > 0)
                .sort((a, b) => b.s - a.s).slice(0, 400).map(x => root.toned(x.r))
        } else if (root.group === -2) {
            const byE = {}
            root.all.forEach(r => { byE[r.e] = r; if (r.s) r.s.forEach(s => byE[s.e] = { e: s.e, n: s.n, a: s.a, g: r.g, k: r.k }) })
            rows = root.recents.map(e => byE[e]).filter(r => !!r)
        } else {
            rows = root.all.filter(r => root.group === -1 || r.g === root.group).map(r => root.toned(r))
        }
        root.results = rows
        root.sel = Math.max(0, Math.min(root.sel, rows.length - 1))
        grid.positionViewAtIndex(root.sel, GridView.Contain)
    }
    function open() { root.query = ""; root.variants = false; root.variantOf = null; root.sel = 0; root.status = ""
        root.group = root.recents.length ? -2 : -1; root.autoTab = true; root.opened = true; statusProc.running = true; root.refresh() }
    function close() { root.opened = false }
    function move(d) { if (!root.results.length) return
        root.sel = Math.max(0, Math.min(root.results.length - 1, root.sel + d)); grid.positionViewAtIndex(root.sel, GridView.Contain) }
    function cycleTab(d) { const i = root.tabs.indexOf(root.group); root.group = root.tabs[(i + d + root.tabs.length) % root.tabs.length]
        root.sel = 0; root.query = ""; root.refresh() }
    function showVariants() {
        const cur = root.results[root.sel]; if (!cur) return
        const base = root.all.find(r => r.e === cur.e || (r.s && r.s.some(s => s.e === cur.e)))
        if (!base || !base.s) { root.status = "No skin-tone variants for this emoji"; return }
        root.variantOf = base; root.variants = true; root.sel = 0; root.refresh()
    }
    function pick(i) {
        const row = root.results[i === undefined ? root.sel : i]; if (!row || picker.running) return
        picker.command = ["python3", Quickshell.shellPath("emoji.py"), "pick", root.hex(row.e)]
        picker.running = true
    }
    function handleKey(k, mods) {
        if (k === Qt.Key_Escape) { if (root.variants) { root.variants = false; root.variantOf = null; root.sel = 0; root.refresh() } else root.close() }
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (mods & (Qt.ControlModifier | Qt.ShiftModifier)) root.showVariants(); else root.pick() }
        else if (k === Qt.Key_Right) root.move(1)
        else if (k === Qt.Key_Left) root.move(-1)
        else if (k === Qt.Key_Down) root.move(root.columns)
        else if (k === Qt.Key_Up) root.move(-root.columns)
        else if (k === Qt.Key_PageDown) root.move(root.columns * 5)
        else if (k === Qt.Key_PageUp) root.move(-root.columns * 5)
        else if (k === Qt.Key_Tab) root.cycleTab(1)
        else if (k === Qt.Key_Backtab) root.cycleTab(-1)
        else if ((mods & Qt.AltModifier) && k >= Qt.Key_0 && k <= Qt.Key_5) { root.tone = k - Qt.Key_0; root.refresh() }
        else return false
        return true
    }

    FileView { path: Quickshell.shellPath("emoji.json")
        onLoaded: { try { const d = JSON.parse(text()); root.all = d.emoji; root.groups = d.groups } catch (e) { root.status = "emoji.json is unreadable" } root.refresh() }
        onLoadFailed: root.status = "emoji.json is missing: run tools/build-emoji-data.py" }
    Process { id: statusProc; command: ["python3", Quickshell.shellPath("emoji.py"), "status"]
        stdout: StdioCollector { onStreamFinished: { try { const s = JSON.parse(text); root.assets = s.assets; root.assetsReady = s.ready; root.recents = s.recents
            if (root.autoTab && !root.query.length) root.group = s.recents.length ? -2 : -1
            root.autoTab = false } catch (e) {} root.refresh() } } }
    Process { id: fetchProc; command: ["python3", Quickshell.shellPath("emoji.py"), "assets"]
        stdout: StdioCollector { onStreamFinished: { try { const s = JSON.parse(text); root.assets = s.assets; root.assetsReady = s.ready } catch (e) {} } }
        onExited: code => { root.fetching = false; root.status = code === 0 ? "" : "Could not fetch Twemoji (offline?). Showing font emoji." } }
    Process { id: picker
        stdout: StdioCollector { onStreamFinished: { let ok = false; try { ok = JSON.parse(text).ok } catch (e) {}
            if (ok) root.close(); else root.status = "Copy failed: is wl-copy installed?" } } }

    IpcHandler {
        target: "emoji"
        function open(): void { root.open() }
        function close(): void { root.close() }
        function toggle(): void { if (root.opened) root.close(); else root.open() }
        // test hooks: type a query, press a key by name, read back the selection
        function type(text: string): void { root.autoTab = false; root.query = text; root.sel = 0; root.refresh() }
        function press(k: string): void { const m = { Left: Qt.Key_Left, Right: Qt.Key_Right, Up: Qt.Key_Up, Down: Qt.Key_Down, Return: Qt.Key_Return,
            Escape: Qt.Key_Escape, Tab: Qt.Key_Tab, Variants: Qt.Key_Return }; root.handleKey(m[k] || 0, k === "Variants" ? Qt.ControlModifier : 0) }
        function setTone(t: int): void { root.tone = t; root.refresh() }
        function selected(): string { const r = root.results[root.sel]; return r ? r.e : "" }
    }

    PanelWindow {
        id: win
        visible: root.opened
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "galaxy-emoji"
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusive only while open; when the surface unmaps the compositor hands focus back to the previous window.
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle { anchors.fill: parent; color: "#8007060d"; MouseArea { anchors.fill: parent; onClicked: root.close() } }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 620; height: 560; radius: Galaxy.radiusWindow; color: "transparent"
            Nebula { anchors.fill: parent; radius: card.radius; seed: 41; glow: 1.1; hot: true }
            MouseArea { anchors.fill: parent }
            scale: root.opened ? 1 : 0.95
            Behavior on scale { SpringAnimation { spring: 4; damping: 0.3 } }
            Connections { target: root; function onOpenedChanged() { if (root.opened) { field.text = ""; field.forceActiveFocus() } } }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 18; spacing: 10
                RowLayout { Layout.fillWidth: true; spacing: 10
                    Text { text: "✦  E M O J I"; font.family: Galaxy.font; font.pixelSize: 13; color: Galaxy.lavender }
                    Item { Layout.fillWidth: true }
                    Repeater { model: 6
                        Rectangle { required property int index
                            implicitWidth: 22; implicitHeight: 22; radius: 11
                            color: ["#ffcc4d", "#f7dece", "#f3d2a2", "#d5ab88", "#af7e57", "#7c533e"][index]
                            border.width: root.tone === index ? 2 : 1; border.color: root.tone === index ? Galaxy.lavender : Galaxy.line
                            MouseArea { anchors.fill: parent; onClicked: { root.tone = parent.index; root.refresh(); field.forceActiveFocus() } } } }
                }
                TextField {
                    id: field
                    Layout.fillWidth: true
                    placeholderText: "search the galaxy…  (name or keyword)"
                    color: Galaxy.ink; placeholderTextColor: Galaxy.dim; selectionColor: Galaxy.violet
                    font.family: Galaxy.font; font.pixelSize: 15; padding: 11
                    background: Rectangle { radius: Galaxy.radiusControl; color: Galaxy.base; border.color: field.activeFocus ? Galaxy.purple : Galaxy.line }
                    onTextEdited: { root.query = text; root.variants = false; root.sel = 0; root.refresh() }
                    Keys.onPressed: e => { if (root.handleKey(e.key, e.modifiers)) e.accepted = true }
                    Connections { target: root; function onQueryChanged() { if (field.text !== root.query) field.text = root.query } }
                }
                RowLayout { Layout.fillWidth: true; spacing: 6; visible: !root.query.length && !root.variants
                    Repeater { model: root.tabs
                        Rectangle { required property int modelData
                            readonly property bool on: root.group === modelData
                            Layout.fillWidth: true; implicitHeight: 26; radius: 13
                            color: on ? Galaxy.raised : "transparent"; border.color: on ? Galaxy.purple : Galaxy.line
                            Text { anchors.centerIn: parent; font.family: Galaxy.font; font.pixelSize: 10; color: parent.on ? Galaxy.ink : Galaxy.label
                                text: root.tabLabels[String(parent.modelData)] || (root.groups[parent.modelData] || "") }
                            MouseArea { anchors.fill: parent; onClicked: { root.group = parent.modelData; root.sel = 0; root.refresh(); field.forceActiveFocus() } } } }
                }
                Text { visible: root.variants; text: "Skin-tone variants · Esc to go back"; font.family: Galaxy.font; font.pixelSize: 11; color: Galaxy.label }
                GridView {
                    id: grid
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    cellWidth: Math.floor(width / root.columns); cellHeight: cellWidth
                    model: root.results
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Item {
                        id: cell
                        required property var modelData; required property int index
                        width: grid.cellWidth; height: grid.cellHeight
                        readonly property string src: root.art(modelData)
                        Rectangle { anchors.fill: parent; anchors.margins: 3; radius: Galaxy.radiusControl
                            color: root.sel === cell.index ? Galaxy.raised : "transparent"
                            border.width: root.sel === cell.index ? 1 : 0; border.color: Galaxy.purple }
                        Image { visible: cell.src.length > 0; anchors.centerIn: parent; width: parent.width - 20; height: width
                            source: cell.src; sourceSize.width: 72; sourceSize.height: 72; asynchronous: true; smooth: true }
                        Text { visible: cell.src.length === 0; anchors.centerIn: parent; text: cell.modelData.e; font.pixelSize: parent.width - 26 }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onEntered: root.sel = cell.index
                            onClicked: m => { root.sel = cell.index; if (m.button === Qt.RightButton) root.showVariants(); else root.pick(cell.index) } }
                    }
                    Text { anchors.centerIn: parent; visible: !root.results.length; font.family: Galaxy.font; font.pixelSize: 13; color: Galaxy.dim
                        text: root.query.length ? "No emoji match “" + root.query + "”" : root.group === -2 ? "Nothing picked yet" : "" }
                }
                RowLayout { Layout.fillWidth: true; spacing: 10
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; font.family: Galaxy.font; font.pixelSize: 12
                        color: root.status.length ? Galaxy.warn : Galaxy.ink
                        text: root.status.length ? root.status : (root.results[root.sel] ? root.results[root.sel].n : "") }
                    GalaxyButton { visible: !root.assetsReady; text: root.fetching ? "Fetching…" : "Get Twemoji art"; enabled: !root.fetching
                        hint: "One download of the pinned Twemoji 15.0.0 SVG set (checksum verified)"
                        onClicked: { root.fetching = true; fetchProc.running = true } }
                }
                Text { Layout.fillWidth: true; font.family: Galaxy.font; font.pixelSize: 10; color: Galaxy.dim; horizontalAlignment: Text.AlignHCenter
                    text: "←→↑↓ move · Enter copy · Ctrl+Enter variants · Alt+0–5 skin tone · Tab category · Esc close" }
                Text { Layout.fillWidth: true; font.family: Galaxy.font; font.pixelSize: 9; color: Galaxy.dim; horizontalAlignment: Text.AlignHCenter
                    text: "Artwork: Twemoji © Twitter, Inc and other contributors, CC-BY 4.0" }
            }
        }
    }
}
