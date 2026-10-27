import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris

ShellRoot {
    id: root
    property var player: Mpris.players.values.find(p => /kopuz/i.test(p.identity + " " + p.dbusName)) ?? null
    property string song: player ? player.trackTitle : "Waiting for Kopuz"
    property string artist: player ? player.trackArtist : "Play something from your galaxy"
    property string trackKey: player ? player.uniqueId + "\n" + artist + "\n" + song : ""
    property var lyricLines: []
    property string lyricSource: ""
    property real playbackPosition: 0
    property real lyricOffset: 0          // manual nudge, seconds; + shows lines earlier (saved per track)
    property var lyricCands: []
    property int candIndex: 0
    property real mvOffset: 0             // auto: player length − lyric duration when the video has a longer intro
    property var offsetStore: ({})
    readonly property real effectiveOffset: lyricOffset - mvOffset
    function applyCandidate(i) {
        if (!lyricCands.length) return
        candIndex = (i + lyricCands.length) % lyricCands.length
        const c = lyricCands[candIndex]
        lyricLines = c.lines || []; lyricText = c.text || ""; lyricUrl = c.url || ""
        lyricSource = (c.source || "") + (lyricCands.length > 1 ? "  " + (candIndex + 1) + "/" + lyricCands.length : "")
        const len = player && player.lengthSupported ? player.length : 0
        const d = len && c.duration ? len - c.duration : 0
        mvOffset = (lyricLines.length && d > 3) ? Math.round(d * 4) / 4 : 0
    }
    function nudge(dv) { lyricOffset = Math.round((lyricOffset + dv) * 100) / 100; saveOffset() }
    function saveOffset() {
        if (!trackKey) return
        const st = Object.assign({}, offsetStore); st[trackKey] = { offset: lyricOffset, index: candIndex }
        offsetStore = st; offFile.setText(JSON.stringify(st))
    }
    FileView { id: offFile; path: Quickshell.env("HOME") + "/.cache/galaxy-lyrics/offsets.json"; blockLoading: true
        Component.onCompleted: { try { root.offsetStore = JSON.parse(text()) } catch (e) { root.offsetStore = {} } } }
    property bool forceRefresh: false
    property int activeLine: {
        let current = -1
        for (let i = 0; i < lyricLines.length; ++i) {
            if (lyricLines[i].time > playbackPosition + effectiveOffset) break
            current = i
        }
        return current
    }
    property real mediaPos: 0
    function fmt(t) { t = Math.max(0, Math.floor(t || 0)); return Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0") }
    Timer { interval: 500; repeat: true; running: root.mediaOpen && !!root.player && !root.lyricsOpen; onTriggered: root.mediaPos = root.player.positionSupported ? root.player.position : 0 }
    Timer {
        interval: 100; repeat: true; running: root.lyricsOpen && !!root.player
        onTriggered: {
            root.playbackPosition = root.player.positionSupported ? root.player.position : 0
            root.mediaPos = root.playbackPosition
        }
    }
    property var levels: []
    property string lyricText: ""
    property string lyricUrl: ""
    property string lyricKey: ""
    property bool mediaOpen: true
    property bool lyricsOpen: false
    onTrackKeyChanged: { lyricLines = []; lyricCands = []; mvOffset = 0; lyricOffset = (offsetStore[trackKey] || {}).offset || 0; lyricText = ""; playbackPosition = 0; if (lyricsOpen) debounce.restart() }
    function fetchLyrics() {
        if (!player || !player.trackTitle) { lyricText = "Play a song in Kopuz first."; return }
        if (lyricKey === trackKey) return
        if (fetcher.running && fetcher.requestKey === trackKey) return
        if (fetcher.running) { fetcher.running = false; debounce.restart(); return }
        fetcher.requestKey = trackKey
        lyricText = "Finding synced lyrics…"
        lyricLines = []; lyricSource = ""
        lyricUrl = ""
        fetcher.command = ["python3", Quickshell.shellPath("lyrics.py"), song, artist, player.trackAlbum, String(player.lengthSupported ? player.length : 0), trackKey].concat(forceRefresh ? ["refresh"] : [])
        forceRefresh = false
        fetcher.running = true
    }
    IpcHandler {
        target: "galaxy"
        function showMedia(): void { root.lyricsOpen = false; root.mediaOpen = true }
        function openLyrics(): void { root.lyricsOpen = true; root.fetchLyrics() }
        function open(): void { root.mediaOpen = true }
        function close(): void { root.lyricsOpen = false; root.mediaOpen = false }
        function toggle(): void { root.mediaOpen = !root.mediaOpen; if (!root.mediaOpen) root.lyricsOpen = false }
        function closeLyrics(): void { root.lyricsOpen = false }
        function testLyricsDrag(dx: int, dy: int): void { lyricsBox.x = Math.max(0, Math.min(lyrics.width - lyricsBox.width, lyricsBox.x + dx)); lyricsBox.y = Math.max(0, Math.min(lyrics.height - lyricsBox.height, lyricsBox.y + dy)) }
        function where(): string { return JSON.stringify({ target: [Math.round(desktop.targetLeft), Math.round(desktop.targetTop)], shown: [Math.round(desktop.posX), Math.round(desktop.posY)], lyrics: [Math.round(lyricsBox.x), Math.round(lyricsBox.y)] }) }
        // test: press at window point (60,60), move the *screen* cursor by (dx,dy) in 20 steps, release
        function testDrag(dx: int, dy: int): void { dragSim.dx = dx; dragSim.dy = dy; dragSim.i = 0
            dragSim.sx = desktop.targetLeft + 60; dragSim.sy = desktop.targetTop + 60; desktop.dragBegin(dragSim.sx, dragSim.sy); dragSim.start() }
    }
    Timer { id: dragSim; interval: 16; repeat: true; property int i; property real dx; property real dy; property real sx; property real sy
        onTriggered: { i++; const cx = sx + dx * i / 20, cy = sy + dy * i / 20
            desktop.dragTo(cx, cy)
            if (i >= 20) { stop(); desktop.dragEnd() } } }
    Timer { id: debounce; interval: 250; onTriggered: root.fetchLyrics() }
    function seekTo(t) { if (player && player.canSeek) { player.position = Math.max(0, t - effectiveOffset); playbackPosition = player.position } }
    // window geometry + lyric offset survive restarts
    property bool geoLoaded: false
    FileView {
        id: geoFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/galaxy-media.json"
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const g = JSON.parse(text())
                if (g.w) desktop.widgetWidth = Math.max(desktop.minW, Math.min(desktop.maxW, g.w))
                if (g.h) desktop.widgetHeight = Math.max(desktop.minH, Math.min(desktop.maxH, g.h))
                if (g.x !== undefined) desktop.targetLeft = g.x   // keep margins bound to target (assigning margins broke the binding)
                if (g.y !== undefined) desktop.targetTop = g.y
                
            } catch (e) {}
            root.geoLoaded = true
        }
        onLoadFailed: root.geoLoaded = true
    }
    Timer { id: saveGeo; interval: 600; onTriggered: geoFile.setText(JSON.stringify({ w: desktop.widgetWidth, h: desktop.widgetHeight, x: Math.round(desktop.targetLeft), y: Math.round(desktop.targetTop) })) }
    Process {
        id: fetcher
        property string requestKey: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim()) return
                try {
                    const result = JSON.parse(text)
                    if (result.request_key !== root.trackKey) { if (root.lyricsOpen) debounce.restart(); return }
                    root.lyricText = result.text; root.lyricUrl = result.url || ""
                    root.lyricLines = result.lines || []; root.lyricSource = result.source || ""
                    root.lyricCands = result.candidates || []; root.mvOffset = 0
                    const saved = root.offsetStore[root.trackKey]
                    root.lyricOffset = saved ? (saved.offset || 0) : 0
                    if (root.lyricCands.length) root.applyCandidate(saved ? (saved.index || 0) : 0)
                    root.lyricKey = result.ok ? root.trackKey : ""
                }
                catch (e) { root.lyricKey = ""; root.lyricText = "Couldn't load lyrics. Try Refetch." }
            }
        }
    }
    Process {
        running: root.mediaOpen && !!root.player && root.player.isPlaying
        command: ["cava", "-p", Quickshell.shellPath("cava.conf")]
        stdout: SplitParser {
            onRead: data => { root.levels = data.split(";").filter(v => v.length).map(v => Math.max(0, Math.min(100, Number(v)))) }
        }
        onRunningChanged: { if (!running) root.levels = [] }
    }
    PanelWindow {
        id: desktop
        visible: root.mediaOpen
        // Fullscreen, input-masked to the card: item coords == screen coords, so drags
        // are 1:1 with the cursor (moving the surface itself under the pointer caused feedback).
        anchors { top: true; left: true; right: true; bottom: true }
        readonly property real minW: 320
        readonly property real minH: 440
        readonly property real maxW: Math.min(900, screen ? screen.width : 900)
        readonly property real maxH: Math.min(1100, screen ? screen.height : 1100)
        readonly property real pad: 18          // transparent room for wobble/overshoot
        property real widgetWidth: 420
        property real widgetHeight: 580
        // drag target; the real margins chase it with a spring (slight overshoot)
        property real targetLeft: Math.max(0, ((screen ? screen.width : 1920) - widgetWidth) / 2)
        property real targetTop: Math.max(0, ((screen ? screen.height : 1080) - widgetHeight) / 2)
        property real velX: 0
        // shown position: follows target exactly while dragging/resizing, springs only on release/clamp
        property real posX: targetLeft
        property real posY: targetTop
        Behavior on posX { enabled: !resizer.active && !desktop.dragging; SpringAnimation { spring: 5; damping: 0.4; mass: 0.8; epsilon: 0.5 } }
        Behavior on posY { enabled: !resizer.active && !desktop.dragging; SpringAnimation { spring: 5; damping: 0.4; mass: 0.8; epsilon: 0.5 } }
        mask: Region { item: mediaCard }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "galaxy-media"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        function clampPos() {
            const sw = screen ? screen.width : 1920, sh = screen ? screen.height : 1080
            targetLeft = Math.max(0, Math.min(sw - widgetWidth, targetLeft))
            targetTop = Math.max(0, Math.min(sh - widgetHeight, targetTop))
        }
        QtObject { id: resizer; property bool active: false }
        // Layer-shell surfaces have no global position in Qt (mapToGlobal ≈ local), and the
        // surface moves under the cursor while dragging, so derive the screen point ourselves:
        // screen = point in window + the surface's current margins.
        property point dragOrigin
        property point dragLast
        property real dragStartL
        property real dragStartT
        property bool dragArmed: false
        property bool dragging: false
        // sx/sy are screen coords (window item coords; the window is fullscreen at 0,0)
        function dragBegin(sx, sy) { dragOrigin = Qt.point(sx, sy); dragLast = dragOrigin; dragStartL = targetLeft; dragStartT = targetTop; dragArmed = true; dragging = false }
        function dragTo(sx, sy) {
            if (!dragArmed) return
            const dx = sx - dragOrigin.x, dy = sy - dragOrigin.y
            if (!dragging) { if (Math.abs(dx) < 3 && Math.abs(dy) < 3) return; dragging = true; mediaCard.stretch = 1.03 }   // 3px dead-zone
            targetLeft = dragStartL + dx
            targetTop = dragStartT + dy
            clampPos()
            mediaCard.tilt = Math.max(-6, Math.min(6, (sx - dragLast.x) * 0.3))        // cosmetic only
            mediaCard.stretch = 1.03 + Math.min(0.02, Math.abs(sy - dragLast.y) * 0.0015)
            dragLast = Qt.point(sx, sy)
        }
        function dragEnd() { dragArmed = false; dragging = false; mediaCard.tilt = 0; mediaCard.stretch = 1; clampPos(); saveGeo.restart() }

        Rectangle {
            id: mediaCard
            x: desktop.posX + desktop.pad; y: desktop.posY + desktop.pad
            width: desktop.widgetWidth - 2 * desktop.pad; height: desktop.widgetHeight - 2 * desktop.pad
            property real tilt: 0
            property real stretch: 1
            rotation: tilt
            transformOrigin: Item.Center
            scale: stretch
            Behavior on tilt { SpringAnimation { spring: 3.2; damping: 0.16; mass: 1 } }
            Behavior on stretch { SpringAnimation { spring: 3.5; damping: 0.2; mass: 1 } }
            radius: 24
            color: "transparent"
            antialiasing: true
            Nebula { anchors.fill: parent; radius: mediaCard.radius; seed: 3; hot: !!root.player && root.player.isPlaying }

            // drag from anywhere on the card; buttons/handles above take their own clicks
            MouseArea {
                id: dragArea
                anchors.fill: parent
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true
                function wp(mouse) { return mapToItem(desktop.contentItem, mouse.x, mouse.y) }
                onPressed: mouse => { const w = wp(mouse); desktop.dragBegin(w.x, w.y) }
                onPositionChanged: mouse => { if (pressed) { const w = wp(mouse); desktop.dragTo(w.x, w.y) } }
                onReleased: desktop.dragEnd()
                onCanceled: desktop.dragEnd()
                onDoubleClicked: { root.lyricsOpen = !root.lyricsOpen; if (root.lyricsOpen) root.fetchLyrics() }
            }

            Column {
                id: mediaContents
                property real sizeFactor: Math.min((mediaCard.width - 40) / 332, (mediaCard.height - 36) / Math.max(1, implicitHeight))
                anchors.centerIn: parent; spacing: 14; width: 332
                scale: sizeFactor
                transformOrigin: Item.Center
                RowLayout {
                    width: parent.width; height: 36; spacing: 8
                    Text { font.family: "Cellforge"
                        Layout.fillWidth: true; Layout.fillHeight: true
                        text: "✦  O R B I T / K O P U Z"; color: "#d4b8ff"; font.pixelSize: 12
                        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                    }
                    StatusPill {
                        state_: !root.player ? "idle" : root.player.isPlaying ? "ok" : "warn"
                        text: !root.player ? "OFFLINE" : root.player.isPlaying ? "PLAYING" : "PAUSED"
                    }
                    GalaxyButton { text: "󰍉"; implicitWidth: 36; hint: "Lyrics (or double-click the card)"; selected: root.lyricsOpen; onClicked: { root.lyricsOpen = !root.lyricsOpen; if (root.lyricsOpen) root.fetchLyrics() } }
                    GalaxyButton {
                        text: "×"; implicitWidth: 36
                        Accessible.name: "Close media widget"
                        onClicked: { mediaCard.tilt = 0; mediaCard.stretch = 1; root.mediaOpen = false }
                    }
                }
                AlbumArt {
                    width: 212; height: 212; anchors.horizontalCenter: parent.horizontalCenter
                    source: root.player ? root.player.trackArtUrl : ""
                    playing: !!root.player && root.player.isPlaying
                }
                Column {
                    width: parent.width; spacing: 5
                    Text { font.family: "Cellforge"; width: parent.width; text: root.song; textFormat: Text.PlainText; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; color: "#f2f0ff"; font.pixelSize: 18; font.bold: true }
                    Text { font.family: "Cellforge"; width: parent.width; text: root.artist; textFormat: Text.PlainText; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; color: "#9a96b3"; font.pixelSize: 12 }
                }
                // seek bar
                Item {
                    width: parent.width; height: 22
                    visible: !!root.player && root.player.lengthSupported && root.player.length > 0
                    Text { font.family: "Zerodot"; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: root.fmt(root.mediaPos); color: "#9a96b3"; font.pixelSize: 10 }
                    Text { font.family: "Zerodot"; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.fmt(root.player ? root.player.length : 0); color: "#9a96b3"; font.pixelSize: 10 }
                    Rectangle {
                        id: seekTrack
                        readonly property real frac: Math.max(0, Math.min(1, root.player && root.player.length > 0 ? root.mediaPos / root.player.length : 0))
                        anchors.verticalCenter: parent.verticalCenter; x: 40; width: parent.width - 80; height: 4; radius: 2; color: "#221c3a"
                        Rectangle { width: parent.width * seekTrack.frac; height: parent.height; radius: 2; color: "#9d6bff"
                            Behavior on width { NumberAnimation { duration: 480 } } }
                        // comet head: soft halo + bright core
                        Rectangle { x: parent.width * seekTrack.frac - 7; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7; color: "#40b46bff"
                            Behavior on x { NumberAnimation { duration: 480 } }
                            Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "#f2f0ff"; border.color: "#d4b8ff"; border.width: 1 } }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor
                            enabled: !!root.player && root.player.canSeek
                            onClicked: mouse => { root.player.position = Math.max(0, Math.min(1, (mouse.x - 8) / seekTrack.width)) * root.player.length; root.mediaPos = root.player.position }
                        }
                    }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; spacing: 3; height: 32
                    Repeater {
                        model: 40
                        Rectangle {
                            required property int index
                            width: 5; radius: 2.5
                            height: Math.max(2, (root.levels[index] || 0) * 0.32)
                            anchors.verticalCenter: parent.verticalCenter
                            // violet → magenta → lilac across the spectrum (solid per bar: no gradient seams)
                            readonly property real t: index / 39
                            color: t < 0.5 ? Qt.tint("#7c4dff", Qt.rgba(1, 0.42, 0.84, t * 1.3))
                                           : Qt.tint("#c86bf0", Qt.rgba(0.83, 0.72, 1, (t - 0.5) * 1.6))
                            opacity: 0.55 + Math.min(0.45, height / 70)
                            Behavior on height { NumberAnimation { duration: 65 } }
                        }
                    }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
                    GalaxyButton {
                        text: "󰒟"; implicitWidth: 44
                        selected: !!root.player && root.player.shuffle
                        enabled: !!root.player && root.player.canControl && root.player.shuffleSupported
                        hint: "Shuffle " + (selected ? "on" : "off")
                        Accessible.name: hint
                        onClicked: root.player.shuffle = !root.player.shuffle
                    }
                    GalaxyButton { text: "󰒮"; enabled: !!root.player && root.player.canGoPrevious; onClicked: root.player.previous() }
                    GalaxyButton { primary: true; text: root.player && root.player.isPlaying ? "󰏤" : "󰐊"; enabled: !!root.player && root.player.canTogglePlaying; onClicked: root.player.togglePlaying() }
                    GalaxyButton { text: "󰒭"; enabled: !!root.player && root.player.canGoNext; onClicked: root.player.next() }
                    GalaxyButton {
                        text: root.player && root.player.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                        implicitWidth: 44
                        selected: !!root.player && root.player.loopState !== MprisLoopState.None
                        enabled: !!root.player && root.player.canControl && root.player.loopSupported
                        hint: !root.player || root.player.loopState === MprisLoopState.None ? "No loop · click to repeat all" : root.player.loopState === MprisLoopState.Playlist ? "Loop all · click to repeat one" : "Loop 1 · click to turn off"
                        Accessible.name: hint
                        onClicked: {
                            const state = root.player.loopState
                            root.player.loopState = state === MprisLoopState.None ? MprisLoopState.Playlist : state === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None
                        }
                    }
                }
            }

            // resize handles: edges + corners (left/top edges move the window too)
            component Edge: MouseArea {
                property bool l: false; property bool r: false; property bool t: false; property bool b: false
                hoverEnabled: true
                cursorShape: (l && t) || (r && b) ? Qt.SizeFDiagCursor : (r && t) || (l && b) ? Qt.SizeBDiagCursor : (l || r) ? Qt.SizeHorCursor : Qt.SizeVerCursor
                property point o; property real w0; property real h0; property real x0; property real y0
                onPressed: mouse => { o = mapToGlobal(mouse.x, mouse.y); w0 = desktop.widgetWidth; h0 = desktop.widgetHeight; x0 = desktop.targetLeft; y0 = desktop.targetTop; resizer.active = true; mediaCard.tilt = 0; mediaCard.stretch = 1 }
                onPositionChanged: mouse => {
                    if (!pressed) return
                    const p = mapToGlobal(mouse.x, mouse.y), dx = p.x - o.x, dy = p.y - o.y
                    if (r) desktop.widgetWidth = Math.max(desktop.minW, Math.min(desktop.maxW, w0 + dx))
                    if (b) desktop.widgetHeight = Math.max(desktop.minH, Math.min(desktop.maxH, h0 + dy))
                    if (l) { const w = Math.max(desktop.minW, Math.min(desktop.maxW, w0 - dx)); desktop.targetLeft = x0 + (w0 - w); desktop.widgetWidth = w }
                    if (t) { const h = Math.max(desktop.minH, Math.min(desktop.maxH, h0 - dy)); desktop.targetTop = y0 + (h0 - h); desktop.widgetHeight = h }
                }
                onReleased: { resizer.active = false; desktop.clampPos(); saveGeo.restart() }
            }
            Edge { r: true; anchors { right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 24; bottomMargin: 24 } width: 8 }
            Edge { l: true; anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 24; bottomMargin: 24 } width: 8 }
            Edge { b: true; anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 24; rightMargin: 24 } height: 8 }
            Edge { t: true; anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: 24; rightMargin: 24 } height: 6 }
            Edge { t: true; l: true; anchors { top: parent.top; left: parent.left } width: 22; height: 22 }
            Edge { t: true; r: true; anchors { top: parent.top; right: parent.right } width: 22; height: 22 }
            Edge { b: true; l: true; anchors { bottom: parent.bottom; left: parent.left } width: 22; height: 22 }
            Edge {
                id: brCorner
                b: true; r: true; anchors { bottom: parent.bottom; right: parent.right } width: 26; height: 26
                Text { anchors.centerIn: parent; text: "◢"; color: brCorner.containsMouse || brCorner.pressed ? "#d4b8ff" : "#3a2f5c"; font.pixelSize: 13 }
            }
        }
    }
    PanelWindow {
        id: lyrics
        anchors { top: true; left: true; right: true; bottom: true }
        mask: Region { item: lyricsBox }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "galaxy-lyrics"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        visible: root.lyricsOpen
        color: "transparent"
        Item { id: lyricsBox; x: 420; y: 70; width: 460; height: 640
        Nebula { anchors.fill: parent; radius: 22; seed: 19; glow: 1.15 }
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 22; spacing: 12
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Text { font.family: "Cellforge";
                    Layout.fillWidth: true; text: "✦  L Y R I C S" + (root.mvOffset > 0 ? "   ·  MV +" + root.mvOffset.toFixed(2) + "s" : ""); color: "#d4b8ff"; font.pixelSize: 12; elide: Text.ElideRight
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; onWheel: w => root.nudge(w.angleDelta.y > 0 ? 0.25 : -0.25) }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.SizeAllCursor
                        property point dragOrigin
                        property real initialLeft
                        property real initialTop
                        onPressed: mouse => {
                            dragOrigin = mapToItem(lyrics.contentItem, mouse.x, mouse.y)
                            initialLeft = lyricsBox.x; initialTop = lyricsBox.y
                        }
                        onPositionChanged: mouse => {
                            if (!pressed) return
                            const point = mapToItem(lyrics.contentItem, mouse.x, mouse.y)
                            lyricsBox.x = Math.max(0, Math.min(lyrics.width - lyricsBox.width, initialLeft + point.x - dragOrigin.x))
                            lyricsBox.y = Math.max(0, Math.min(lyrics.height - lyricsBox.height, initialTop + point.y - dragOrigin.y))
                        }
                    }
                }
                StatusPill {
                    state_: fetcher.running ? "busy" : root.lyricLines.length ? "ok" : root.lyricText && root.lyricKey ? "warn" : "idle"
                    text: fetcher.running ? "SEARCHING" : root.lyricLines.length ? "SYNCED" : root.lyricText && root.lyricKey ? "PLAIN" : "NONE"
                }
                GalaxyButton { text: "×"; onClicked: root.lyricsOpen = false; Accessible.name: "Close lyrics" }
            }
            // now playing: art thumb + wrapped title/artist + source
            RowLayout {
                Layout.fillWidth: true; spacing: 14
                AlbumArt { Layout.preferredWidth: 64; Layout.preferredHeight: 64; radius: 12; compact: true
                    source: root.player ? root.player.trackArtUrl : ""; playing: !!root.player && root.player.isPlaying }
                ColumnLayout { Layout.fillWidth: true; spacing: 3
                    Text { font.family: "Cellforge"; Layout.fillWidth: true; text: root.song; textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; color: "#f2f0ff"; font.pixelSize: 19; font.bold: true }
                    Text { font.family: "Cellforge"; Layout.fillWidth: true; text: root.artist; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: "#9a96b3"; font.pixelSize: 12 }
                    Text { font.family: "Zerodot"; Layout.fillWidth: true; visible: root.lyricSource.length > 0; text: root.lyricSource; elide: Text.ElideRight; color: "#8a84a8"; font.pixelSize: 10 }
                }
            }
            // track progress (thin, same comet language as the player's seek bar)
            Item {
                Layout.fillWidth: true; implicitHeight: 14
                visible: !!root.player && root.player.lengthSupported && root.player.length > 0
                readonly property real frac: Math.max(0, Math.min(1, root.player && root.player.length > 0 ? root.mediaPos / root.player.length : 0))
                Text { id: lpL; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; font.family: "Zerodot"; font.pixelSize: 10; color: "#8a84a8"; text: root.fmt(root.mediaPos) }
                Text { id: lpR; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; font.family: "Zerodot"; font.pixelSize: 10; color: "#8a84a8"; text: root.fmt(root.player ? root.player.length : 0) }
                Rectangle { id: lpTrack; anchors.left: lpL.right; anchors.right: lpR.left; anchors.margins: 10; anchors.verticalCenter: parent.verticalCenter; height: 3; radius: 1.5; color: "#221c3a"
                    Rectangle { width: parent.width * parent.parent.frac; height: parent.height; radius: 1.5; color: "#9d6bff" }
                    Rectangle { x: parent.width * parent.parent.frac - 4; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: "#f2f0ff"; border.color: "#b46bff" } }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2147" }
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                visible: root.lyricLines.length > 0
                ListView {
                    id: timedLyrics
                    anchors.fill: parent; clip: true
                    model: root.lyricLines
                    currentIndex: root.activeLine
                    spacing: 6
                    // keep the active line in the optical centre, with room to scroll the first/last lines there
                    header: Item { width: 1; height: timedLyrics.height * 0.35 }
                    footer: Item { width: 1; height: timedLyrics.height * 0.45 }
                    preferredHighlightBegin: height * 0.38; preferredHighlightEnd: height * 0.38 + 40
                    highlightRangeMode: ListView.ApplyRange
                    highlightMoveDuration: 320
                    highlightResizeDuration: 160
                    onModelChanged: Qt.callLater(() => { if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Center) })
                    ScrollBar.vertical: ScrollBar { width: 5; contentItem: Rectangle { radius: 2.5; color: "#3a2f5c" } }
                    highlight: Rectangle {
                        radius: 12; color: "#1c1536"; border.color: "#3a2f5c"
                        Rectangle { x: 0; y: 8; width: 3; height: parent.height - 16; radius: 2; color: "#b46bff" }
                    }
                    delegate: Item {
                        required property var modelData
                        required property int index
                        readonly property bool active: index === root.activeLine
                        width: timedLyrics.width - 12
                        implicitHeight: line.implicitHeight + 14
                        Text { id: line; font.family: "Cellforge"
                            anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 16; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.text || "♪"
                            textFormat: Text.PlainText; wrapMode: Text.Wrap
                            font.pixelSize: active ? 21 : 16; font.bold: active
                            color: lineMouse.containsMouse ? "#f2f0ff" : active ? "#f2f0ff" : index < root.activeLine ? "#5d5878" : "#a49fc0"
                            layer.enabled: active
                            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#b46bff"; shadowBlur: 0.7; blurMax: 24; shadowHorizontalOffset: 0; shadowVerticalOffset: 0; shadowOpacity: 0.9 }
                            opacity: active ? 1 : Math.max(0.35, 0.85 - Math.abs(index - root.activeLine) * 0.08)
                            Behavior on color { ColorAnimation { duration: 180 } }
                            Behavior on font.pixelSize { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                        MouseArea { id: lineMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.seekTo(modelData.time) }
                    }
                }
            }
            ScrollView {
                visible: root.lyricLines.length === 0
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                contentWidth: availableWidth
                TextArea { font.family: "Cellforge";
                    text: root.lyricText; textFormat: TextEdit.PlainText; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                    color: "#f2f0ff"; font.pixelSize: 16; background: null
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Text { font.family: "Cellforge"; text: "SYNC"; color: "#8a84a8"; font.pixelSize: 10; font.letterSpacing: 1.5; Layout.rightMargin: 2 }
                GalaxyButton { text: "−1"; implicitWidth: 34; enabled: root.lyricLines.length > 0; hint: "Lyrics 1s later"; onClicked: root.nudge(-1) }
                GalaxyButton { text: "−¼"; implicitWidth: 34; enabled: root.lyricLines.length > 0; hint: "Lyrics 0.25s later"; onClicked: root.nudge(-0.25) }
                Text { font.family: "Zerodot"; text: (root.lyricOffset >= 0 ? "+" : "") + root.lyricOffset.toFixed(2) + "s"; color: root.lyricOffset === 0 ? "#5d5878" : "#d4b8ff"; font.pixelSize: 12
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.lyricOffset = 0; root.saveOffset() } } }
                GalaxyButton { text: "+¼"; implicitWidth: 34; enabled: root.lyricLines.length > 0; hint: "Lyrics 0.25s earlier"; onClicked: root.nudge(0.25) }
                GalaxyButton { text: "+1"; implicitWidth: 34; enabled: root.lyricLines.length > 0; hint: "Lyrics 1s earlier"; onClicked: root.nudge(1) }
                GalaxyButton { text: "󰒭"; implicitWidth: 34; visible: root.lyricCands.length > 1; hint: "Next lyrics match"; onClicked: { root.applyCandidate(root.candIndex + 1); root.saveOffset() } }
                Item { Layout.fillWidth: true }
                GalaxyButton { visible: root.lyricUrl.length > 0; text: "↗"; implicitWidth: 36; hint: "Open lyrics source"; onClicked: Qt.openUrlExternally(root.lyricUrl) }
                GalaxyButton { text: "󰑐"; implicitWidth: 36; enabled: !fetcher.running; hint: "Refetch: skip the cache and search again"; onClicked: { root.lyricKey = ""; root.forceRefresh = true; root.fetchLyrics() } }
            }
            Text { font.family: "Cellforge"; Layout.fillWidth: true; visible: root.lyricLines.length > 0; text: "Click a line to seek · scroll header to nudge · saved per track"; color: "#5d5878"; font.pixelSize: 10 }
        }
        }
    }
}
