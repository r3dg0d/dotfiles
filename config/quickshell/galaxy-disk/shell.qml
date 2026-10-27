// galaxy-disk — WinDirStat-style disk map for the deep-space rice.
// Open: quickshell ipc -c galaxy-disk call disk open   ·   tab: ... call disk tab <id>
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property bool opened: true
    property var data: ({})
    property var prog: ({ scanning: false })
    property string tab: "overview"
    property var browse: []          // stack of tree nodes
    property var selected: null
    property var cleanable: []
    property string message: ""
    property var confirm: null       // {title,text,kind,arg}
    readonly property string home: "/home/r3dg0d"
    readonly property string py: "/run/current-system/sw/bin/python3"
    readonly property var envv: ({ HOME: "/home/r3dg0d", USER: "r3dg0d", WAYLAND_DISPLAY: "wayland-1", XDG_RUNTIME_DIR: "/run/user/1000",
        PATH: "/home/r3dg0d/.local/bin:/home/r3dg0d/.nix-profile/bin:/etc/profiles/per-user/r3dg0d/bin:/run/current-system/sw/bin" })
    readonly property var catColor: { const m = { other: "#8a84a8" }; (data.categories || []).forEach(c => m[c.id] = c.color); return m }

    function sh(p, args) { p.environment = Object.assign({}, envv, { WAYLAND_DISPLAY: Quickshell.env("WAYLAND_DISPLAY") || "wayland-1", XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000" }); p.command = [py, home + "/.config/quickshell/galaxy-disk/scan.py"].concat(args); p.running = true }
    function human(n) { const u = ["B", "K", "M", "G", "T"]; let i = 0; n = n || 0; while (n >= 1024 && i < 4) { n /= 1024; i++ } return (i ? n.toFixed(n < 10 ? 2 : 1) : n) + " " + u[i] + (i ? "iB" : "") }
    function pretty(p) { return (p || "").replace(home, "~") }
    function cat(id) { return (data.categories || []).find(c => c.id === id) }
    function findNode(path) {
        if (!data.tree) return null
        let best = null
        function rec(n) { if (n.x) return; if (n.p === path) { best = n; return } if (path.startsWith(n.p === "/" ? "/" : n.p + "/")) (n.c || []).forEach(rec) }
        rec(data.tree); return best
    }
    function openBrowse(path) {
        const stack = [data.tree]
        let n = data.tree
        while (n && n.p !== path) { const nx = (n.c || []).find(c => !c.x && (path === c.p || path.startsWith(c.p + "/"))); if (!nx) break; stack.push(nx); n = nx }
        browse = stack; tab = "browse"; selected = null
    }
    function isCleanable(p) { return cleanable.some(c => c.p === p) }
    function load() { sh(resultP, ["result"]); sh(cleanP, ["cleanable"]) }

    IpcHandler { target: "disk"
        function open(): void { root.opened = true; if (!root.data.ok) root.load() }
        function toggle(): void { root.opened = !root.opened }
        function close(): void { root.opened = false }
        function rescan(): void { root.opened = true; root.sh(scanP, ["scan", "--bg"]) }
        function tab(name: string): void { root.opened = true; root.tab = name; root.selected = null }
        function browse(path: string): void { root.opened = true; root.openBrowse(path) } }

    Process { id: resultP; stdout: StdioCollector { onStreamFinished: { try { const j = JSON.parse(text); if (j.ok) { root.data = j; root.browse = [j.tree] } } catch (e) {} } } }
    Process { id: statusP; stdout: StdioCollector { onStreamFinished: { try { const was = root.prog.scanning; root.prog = JSON.parse(text)
        if (was && !root.prog.scanning) { root.load(); root.message = "scan finished" }
        if (!root.prog.scanning && !root.prog.has_result && !scanP.running && !root.autoStarted) { root.autoStarted = true; root.sh(scanP, ["scan", "--bg"]) } } catch (e) {} } } }
    property bool autoStarted: false
    Process { id: scanP; stdout: StdioCollector { onStreamFinished: { try { root.prog = JSON.parse(text) } catch (e) {} } } }
    Process { id: cleanP; stdout: StdioCollector { onStreamFinished: { try { root.cleanable = JSON.parse(text) } catch (e) {} } } }
    Process { id: actP; stdout: StdioCollector { onStreamFinished: { try { root.message = JSON.parse(text).msg || "done" } catch (e) { root.message = text.trim() } if (root.message.startsWith("freed")) root.sh(cleanP, ["cleanable"]) } } }
    Process { id: hubP; stdout: StdioCollector { onStreamFinished: root.message = "opened a Ghostty terminal — type your sudo password there" } }
    Timer { interval: root.prog.scanning ? 500 : 4000; running: root.opened; repeat: true; triggeredOnStart: true; onTriggered: if (!statusP.running) root.sh(statusP, ["status"]) }
    Component.onCompleted: load()

    // squarified treemap: items [{s,...}] -> [{x,y,w,h,item}]
    function squarify(items, W, H) {
        const out = []; const tot = items.reduce((a, b) => a + b.s, 0)
        if (tot <= 0 || W < 2 || H < 2) return out
        const scale = W * H / tot
        let rest = items.filter(i => i.s > 0).map(i => ({ a: i.s * scale, item: i }))
        let x = 0, y = 0, w = W, h = H
        function worst(row, side) { const s = row.reduce((a, b) => a + b.a, 0); let mx = 0, mn = 1e18; row.forEach(r => { mx = Math.max(mx, r.a); mn = Math.min(mn, r.a) }); return Math.max(side * side * mx / (s * s), s * s / (side * side * mn)) }
        while (rest.length) {
            const side = Math.min(w, h); let row = [rest[0]]; let i = 1
            while (i < rest.length && worst(row.concat([rest[i]]), side) <= worst(row, side)) { row.push(rest[i]); i++ }
            rest = rest.slice(i)
            const s = row.reduce((a, b) => a + b.a, 0)
            if (w >= h) { const cw = s / h; let cy = y; row.forEach(r => { const rh = r.a / cw; out.push({ x: x, y: cy, w: cw, h: rh, item: r.item }); cy += rh }); x += cw; w -= cw }
            else { const ch = s / w; let cx = x; row.forEach(r => { const rw = r.a / ch; out.push({ x: cx, y: y, w: rw, h: ch, item: r.item }); cx += rw }); y += ch; h -= ch }
        }
        return out
    }

    // what the current tab shows: [{n,p,s,k,color,kind}] kind: cat | item | node
    readonly property var view: {
        if (!data.ok) return []
        if (tab === "overview") return (data.categories || []).map(c => ({ n: c.name, p: c.id, s: c.size, k: c.id, icon: c.icon, kind: "cat" }))
        if (tab === "browse") { const n = browse[browse.length - 1]; return n ? (n.c || []).map(c => Object.assign({ kind: "node" }, c)).sort((a, b) => b.s - a.s) : [] }
        const c = cat(tab); return c ? c.items.map(i => Object.assign({ kind: "item" }, i)) : []
    }
    readonly property real viewTotal: view.reduce((a, b) => a + b.s, 0)
    function activate(it) {
        if (it.kind === "cat") { tab = it.p; selected = null }
        else if (it.kind === "item") { if (it.store) { selected = it; return } if (findNode(it.p)) openBrowse(it.p); else selected = it }
        else if (it.c && it.c.length && !it.x) { browse = browse.concat([it]); selected = null }
        else selected = it
    }

    component Label2: Text { font.family: "Cellforge"; color: "#8a84a8"; font.pixelSize: 10; font.letterSpacing: 1.5 }

    FloatingWindow {
        id: window
        title: "Galaxy Disk Map"
        visible: root.opened
        implicitWidth: 960; implicitHeight: 720
        minimumSize: Qt.size(720, 560)
        color: "transparent"
        onClosed: root.opened = false
        Nebula { anchors.fill: parent; radius: 22; seed: 29; glow: 0.8 }  // solid #0e0a1c + painted nebula (no gradient seam)

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 18; spacing: 10
            // ── header
            RowLayout { Layout.fillWidth: true; spacing: 10
                Text { Layout.fillWidth: true; font.family: "Cellforge"; text: "✦  O R B I T  /  D I S K   M A P"; font.pixelSize: 12; color: "#d4b8ff"
                    MouseArea { anchors.fill: parent; cursorShape: Qt.SizeAllCursor; onPressed: window.startSystemMove() } }
                Text { font.family: "NullType"; font.pixelSize: 11; color: "#5d5878"
                    text: root.prog.scanning ? "" : root.data.ok ? "scanned " + root.data.scanned_at + " · " + root.data.files.toLocaleString(Qt.locale(), "f", 0) + " files · " + root.data.duration + "s" : "" }
                GalaxyButton { text: root.prog.scanning ? "scanning…" : "󰑓  Rescan"; enabled: !root.prog.scanning; implicitHeight: 30; font.pixelSize: 11; onClicked: { root.sh(scanP, ["scan", "--bg"]); root.message = "" } }
                GalaxyButton { text: "×"; implicitHeight: 30; hint: "Hide"; onClicked: root.opened = false }
            }
            // ── mounts
            RowLayout { Layout.fillWidth: true; spacing: 10
                Repeater { model: root.data.mounts || []
                    Rectangle { required property var modelData; Layout.fillWidth: true; Layout.preferredWidth: modelData.mount === "/" ? 3 : 1
                        implicitHeight: 56; radius: 14; color: "#120f22"; border.color: "#2a2344"
                        ColumnLayout { anchors.fill: parent; anchors.margins: 10; spacing: 5
                            RowLayout { Layout.fillWidth: true
                                Text { font.family: "JetBrainsMono Nerd Font"; text: "󰋊"; color: "#b46bff"; font.pixelSize: 14 }
                                Text { text: modelData.mount + "  " + modelData.fs; font.family: "Cellforge"; font.pixelSize: 11; color: "#f2f0ff" }
                                Item { Layout.fillWidth: true }
                                Text { text: modelData.mount === "/" ? root.human(modelData.free) + " free · " + root.human(modelData.used) + " / " + root.human(modelData.total) : root.human(modelData.free) + " free"; font.family: "NullType"; font.pixelSize: 11; color: "#9a96b3" } }
                            Rectangle { Layout.fillWidth: true; height: 7; radius: 3.5; color: "#26223a"
                                Rectangle { height: parent.height; radius: 3.5; width: parent.width * modelData.pct / 100; color: modelData.pct > 85 ? "#ff6b8f" : "#9b6bff" } } } } }
            }
            // ── tabs
            Flickable { Layout.fillWidth: true; implicitHeight: 32; contentWidth: tabRow.implicitWidth; clip: true; boundsBehavior: Flickable.StopAtBounds
                RowLayout { id: tabRow; spacing: 6
                    Repeater { model: [{ id: "overview", icon: "󰋙", name: "Overview" }].concat(root.data.categories || []).concat([{ id: "browse", icon: "󰙅", name: "Browse" }])
                        GalaxyButton { required property var modelData; implicitHeight: 30; font.pixelSize: 10; implicitWidth: implicitContentWidth + 20
                            text: modelData.icon + "  " + modelData.name; selected: root.tab === modelData.id
                            onClicked: { root.tab = modelData.id; root.selected = null } } } } }
            // ── progress
            Rectangle { Layout.fillWidth: true; visible: !!root.prog.scanning; implicitHeight: 40; radius: 12; color: "#120f22"; border.color: "#5b3d99"
                RowLayout { anchors.fill: parent; anchors.margins: 10; spacing: 10
                    BusyIndicator { implicitWidth: 22; implicitHeight: 22; running: true }
                    Text { Layout.fillWidth: true; elide: Text.ElideMiddle; font.family: "NullType"; font.pixelSize: 11; color: "#d4b8ff"
                        text: (root.prog.phase === "nix" ? "measuring /nix/store · " : "scanning · ") + (root.prog.files || 0).toLocaleString(Qt.locale(), "f", 0) + " files · " + root.human(root.prog.bytes) + " · " + (root.prog.elapsed || 0) + "s · " + root.pretty(root.prog.current) } } }
            // ── breadcrumb (browse) / heading
            RowLayout { Layout.fillWidth: true; spacing: 4
                visible: root.data.ok === true
                Repeater { model: root.tab === "browse" ? root.browse : []
                    RowLayout { required property var modelData; required property int index; spacing: 4
                        Text { visible: index > 0; text: "›"; color: "#5d5878"; font.pixelSize: 13 }
                        Text { text: index === 0 ? "󰋜 all" : modelData.n; font.family: "Cellforge"; font.pixelSize: 11
                            color: index === root.browse.length - 1 ? "#f2f0ff" : "#b46bff"
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.browse = root.browse.slice(0, index + 1); root.selected = null } } } } }
                Text { visible: root.tab !== "browse"; font.family: "Zerodot"; font.pixelSize: 16; color: "#f2f0ff"
                    text: root.tab === "overview" ? "Where your space went" : (root.cat(root.tab) || {}).name || "" }
                Item { Layout.fillWidth: true }
                Text { font.family: "Zerodot"; font.pixelSize: 16; color: "#d4b8ff"; text: root.human(root.tab === "browse" ? (root.browse[root.browse.length - 1] || {}).s : root.viewTotal) }
                GalaxyButton { visible: root.tab === "browse" && root.browse.length > 1; text: "󰁍 Up"; implicitHeight: 26; font.pixelSize: 10
                    onClicked: { root.browse = root.browse.slice(0, -1); root.selected = null } }
            }
            // ── body: treemap + list
            RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
                Rectangle { id: mapBox; Layout.fillWidth: true; Layout.fillHeight: true; radius: 14; color: "#0b0914"; border.color: "#26223a"; clip: true
                    Text { anchors.centerIn: parent; visible: !root.data.ok; color: "#5d5878"; font.family: "Cellforge"; font.pixelSize: 12; text: root.prog.scanning ? "mapping the galaxy…" : "no scan yet" }
                    Item { id: mapArea; anchors.fill: parent; anchors.margins: 6
                        Repeater { model: root.squarify(root.view, mapArea.width, mapArea.height)
                            Rectangle { id: tile; required property var modelData; required property int index
                                readonly property var it: modelData.item
                                readonly property color base: root.catColor[it.k] || "#8a84a8"
                                x: modelData.x + 1.5; y: modelData.y + 1.5; width: Math.max(0, modelData.w - 3); height: Math.max(0, modelData.h - 3); radius: Math.min(8, width / 4, height / 4)
                                color: Qt.rgba(base.r, base.g, base.b, it.x ? 0.10 : (tm.containsMouse ? 0.55 : 0.18 + 0.22 * Math.max(0, 1 - index / 12)))
                                border.color: root.selected && root.selected.p === it.p && root.selected.n === it.n ? "#f2f0ff" : Qt.rgba(base.r, base.g, base.b, 0.8); border.width: 1
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Column { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 7; width: parent.width - 14; spacing: 1
                                    visible: tile.width > 56 && tile.height > 30
                                    Text { width: parent.width; elide: Text.ElideRight; text: (tile.it.icon ? tile.it.icon + " " : "") + tile.it.n; color: "#f2f0ff"; font.family: tile.it.icon ? "JetBrainsMono Nerd Font" : "Cellforge"; font.pixelSize: tile.width > 160 && tile.height > 60 ? 13 : 10 }
                                    Text { visible: tile.height > 44; text: root.human(tile.it.s); color: Qt.lighter(tile.base, 1.3); font.family: "NullType"; font.pixelSize: 10 } }
                                MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (m) => { if (m.button === Qt.RightButton) root.selected = tile.it; else root.activate(tile.it) }
                                    onPositionChanged: (m) => { const p = mapToItem(mapBox, m.x, m.y); tip.show(tile.it, p.x, p.y) }
                                    onExited: tip.it = null } } }
                    }
                    Rectangle { id: tip; property var it: null; visible: !!it; z: 10; radius: 10; color: "#1a1630"; border.color: "#b46bff"
                        width: tipCol.implicitWidth + 20; height: tipCol.implicitHeight + 14
                        function show(i, px, py) { it = i; x = Math.min(px + 14, mapBox.width - width - 4); y = Math.min(py + 14, mapBox.height - height - 4) }
                        Column { id: tipCol; anchors.centerIn: parent; spacing: 2
                            Text { text: tip.it ? tip.it.n : ""; color: "#f2f0ff"; font.family: "Cellforge"; font.pixelSize: 11 }
                            Text { text: tip.it ? root.human(tip.it.s) + "  ·  " + (root.viewTotal ? (100 * tip.it.s / root.viewTotal).toFixed(1) : 0) + "%" + (tip.it.full && tip.it.full !== tip.it.s ? "  (" + root.human(tip.it.full) + " incl. other categories)" : "") : ""; color: "#d4b8ff"; font.family: "NullType"; font.pixelSize: 11 }
                            Text { visible: !!tip.it && tip.it.kind !== "cat"; text: tip.it ? root.pretty(tip.it.p) : ""; color: "#8a84a8"; font.family: "NullType"; font.pixelSize: 10 }
                            Text { text: tip.it ? (tip.it.kind === "cat" || (tip.it.c && tip.it.c.length && !tip.it.x) || (tip.it.kind === "item" && tip.it.d) ? "click to drill in · right-click to select" : "click to select") : ""; color: "#5d5878"; font.family: "NullType"; font.pixelSize: 9 } } }
                }
                // list
                Rectangle { Layout.preferredWidth: 330; Layout.fillHeight: true; radius: 14; color: "#120f22"; border.color: "#2a2344"
                    ColumnLayout { anchors.fill: parent; anchors.margins: 10; spacing: 8
                        ListView { id: lv; Layout.fillWidth: true; Layout.preferredWidth: 10; Layout.fillHeight: true; clip: true; spacing: 3; model: root.view; boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            delegate: Rectangle { id: row; required property var modelData; width: lv.width - 8; height: 40; radius: 9
                                readonly property color base: root.catColor[modelData.k] || "#8a84a8"
                                color: rm.containsMouse || (root.selected && root.selected.p === modelData.p && root.selected.n === modelData.n) ? "#1a1630" : "transparent"
                                Rectangle { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 6; height: 3; radius: 1.5
                                    width: (parent.width - 12) * (root.viewTotal ? row.modelData.s / root.viewTotal : 0); color: row.base }
                                RowLayout { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; anchors.bottomMargin: 6; spacing: 8
                                    Rectangle { width: 8; height: 8; radius: 4; color: row.base }
                                    Text { Layout.fillWidth: true; elide: Text.ElideMiddle; text: row.modelData.n; color: "#f2f0ff"; font.family: "Cellforge"; font.pixelSize: 11 }
                                    Text { text: root.human(row.modelData.s); color: "#d4b8ff"; font.family: "NullType"; font.pixelSize: 11 }
                                    Text { Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight; text: (root.viewTotal ? 100 * row.modelData.s / root.viewTotal : 0).toFixed(1) + "%"; color: "#8a84a8"; font.family: "NullType"; font.pixelSize: 10 } }
                                MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (m) => root.selected = row.modelData; onDoubleClicked: root.activate(row.modelData) } } }
                        // store / caches extras
                        ColumnLayout { Layout.fillWidth: true; spacing: 5; visible: root.tab === "apps"
                            Label2 { Layout.fillWidth: true; elide: Text.ElideRight; text: "NIX STORE  ·  sudo in Ghostty" }
                            GalaxyButton { Layout.fillWidth: true; Layout.preferredWidth: 10; implicitHeight: 28; font.pixelSize: 10; text: "󰃢  GC older than 14 days"
                                onClicked: root.confirm = { title: "Collect garbage?", text: "Deletes system + user generations older than 14 days, then frees unreferenced store paths.\n\nsudo nix-collect-garbage --delete-older-than 14d", kind: "hub", arg: "gc-old" } }
                            GalaxyButton { Layout.fillWidth: true; Layout.preferredWidth: 10; implicitHeight: 28; font.pixelSize: 10; text: "󰆼  Optimise store (hard-link dupes)"
                                onClicked: root.confirm = { title: "Optimise the Nix store?", text: "Hard-links identical files. Safe, but slow on a big store.\n\nsudo nix-store --optimise", kind: "hub", arg: "optimise" } } }
                        ColumnLayout { Layout.fillWidth: true; spacing: 4; visible: root.tab === "caches" && root.cleanable.length > 0
                            Label2 { Layout.fillWidth: true; elide: Text.ElideRight; text: "SAFE TO CLEAN  ·  apps rebuild these" }
                            Repeater { model: root.cleanable.slice(0, 5)
                                RowLayout { required property var modelData; Layout.fillWidth: true; spacing: 6
                                    Text { Layout.fillWidth: true; Layout.preferredWidth: 10; elide: Text.ElideMiddle; text: modelData.n; color: "#9a96b3"; font.family: "NullType"; font.pixelSize: 10 }
                                    Text { text: root.human(modelData.s); color: "#ffc46b"; font.family: "NullType"; font.pixelSize: 10 }
                                    GalaxyButton { implicitHeight: 22; font.pixelSize: 9; text: "clean"
                                        onClicked: root.confirm = { title: "Empty " + modelData.n + "?", text: "Deletes everything inside\n" + modelData.p + "\n(" + root.human(modelData.s) + "). The folder itself stays; apps re-create what they need.", kind: "clean", arg: modelData.p } } } } }
                    }
                }
            }
            // ── selection / actions footer
            Rectangle { Layout.fillWidth: true; implicitHeight: 44; radius: 12; color: "#120f22"; border.color: "#2a2344"
                RowLayout { anchors.fill: parent; anchors.margins: 7; anchors.leftMargin: 12; spacing: 8
                    Text { Layout.fillWidth: true; elide: Text.ElideMiddle; font.family: "NullType"; font.pixelSize: 11
                        color: root.selected ? "#f2f0ff" : "#8a84a8"
                        text: root.selected ? (root.selected.kind === "cat" ? root.selected.n : root.pretty(root.selected.p)) + "  ·  " + root.human(root.selected.s) + (root.selected.store ? "  ·  " + root.selected.gens + " system generations — " + root.selected.note : "")
                              : (root.message || "click a tile to drill in · right-click / single-click a row to select · double-click a row to open") }
                    readonly property bool hasPath: !!root.selected && root.selected.kind !== "cat"
                    GalaxyButton { visible: parent.hasPath; implicitHeight: 28; font.pixelSize: 10; text: "󰉋  Open"; onClicked: root.sh(actP, ["open", root.selected.p]) }
                    GalaxyButton { visible: parent.hasPath; implicitHeight: 28; font.pixelSize: 10; text: "󰆏  Copy path"; onClicked: root.sh(actP, ["copy", root.selected.p]) }
                    GalaxyButton { visible: parent.hasPath && root.isCleanable(root.selected.p); implicitHeight: 28; font.pixelSize: 10; text: "󰃢  Clean"
                        onClicked: root.confirm = { title: "Empty " + root.pretty(root.selected.p) + "?", text: "Deletes everything inside\n" + root.selected.p + "\nThe folder itself stays.", kind: "clean", arg: root.selected.p } }
                }
            }
        }

        // ── confirm dialog
        Rectangle { anchors.fill: parent; radius: 22; color: "#cc07060d"; visible: !!root.confirm
            MouseArea { anchors.fill: parent }
            Rectangle { anchors.centerIn: parent; width: 420; height: dlg.implicitHeight + 36; radius: 18; color: "#120f22"; border.color: "#b46bff"
                ColumnLayout { id: dlg; anchors.fill: parent; anchors.margins: 18; spacing: 12
                    Text { text: root.confirm ? root.confirm.title : ""; color: "#f2f0ff"; font.family: "Zerodot"; font.pixelSize: 16; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    Text { text: root.confirm ? root.confirm.text : ""; color: "#9a96b3"; font.family: "NullType"; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
                    RowLayout { Layout.fillWidth: true; spacing: 8
                        GalaxyButton { Layout.fillWidth: true; text: "Cancel"; onClicked: root.confirm = null }
                        GalaxyButton { Layout.fillWidth: true; primary: true; text: "Yes, do it"
                            onClicked: { const c = root.confirm; root.confirm = null
                                if (c.kind === "clean") root.sh(actP, ["clean", c.arg])
                                else { hubP.environment = root.envv; hubP.command = [root.py, root.home + "/.config/quickshell/galaxy-hub/hub.py", "action", "term", c.arg]; hubP.running = true } } } } } } }
    }
}
