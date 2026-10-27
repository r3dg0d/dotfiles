// galaxy-hub — weather · storage · updater · network panels for the deep-space rice.
// Open:  quickshell ipc -c galaxy-hub call hub toggle <weather|storage|updater|network>
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

ShellRoot {
    id: root
    property string page: "weather"
    property bool open: false
    property var weather: ({})
    property var storage: ({})
    property var updater: ({})
    property var net: ({})
    property var dns: ({})
    property var speed: ({})
    property string status: ""
    property var vms: ({})
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio && (n.name || "").indexOf("alsa_output") === 0)
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio && (n.name || "").indexOf("alsa_input") === 0 && (n.name || "").indexOf(".monitor") < 0)
    function nodeName(n) { return n ? (n.description || n.nickname || n.name) : "no device" }
    property var confirm: null          // {title, text, key, danger}
    readonly property var pages: [
        { id: "weather", icon: "󰖕", label: "Weather" },
        { id: "storage", icon: "󱘲", label: "Storage" },
        { id: "updater", icon: "󰚰", label: "Updates" },
        { id: "constructs", icon: "󰍺", label: "VMs" },
        { id: "audio", icon: "󰕾", label: "Audio" },
        { id: "network", icon: "󰛳", label: "Net" }
    ]
    readonly property string mono: "NullType"
    readonly property string ui: "Cellforge"
    readonly property string led: "Zerodot"

    function show(p) { page = p; open = true; refresh(p) }
    function refresh(p) {
        if (p === "weather") weatherProc.go(["weather"])
        else if (p === "storage") storageProc.go(["storage"])
        else if (p === "updater") updaterProc.go(["updater"])
        else if (p === "network") { netProc.go(["network"]); lastSpeed.go(["last-speedtest"]) }
        else if (p === "constructs") vmProc.go(["constructs", "--refresh"])
    }
    function act(args, then) { actionProc.after = then || ""; actionProc.go(["action"].concat(args)) }
    function ask(title, text, key, danger, extra) { confirm = { title: title, text: text, key: key, danger: !!danger, extra: extra || "" } }

    IpcHandler {
        target: "hub"
        function toggle(p: string): void { if (root.open && root.page === p) root.open = false; else root.show(p) }
        function open(p: string): void { root.show(p) }
        function close(): void { root.open = false }
    }

    component Backend: Process {
        id: proc
        property var target: null
        signal done(var data)
        function go(args) { if (running) return; command = ["python3", Quickshell.shellPath("hub.py")].concat(args); running = true }
        stdout: StdioCollector {
            onStreamFinished: { try { proc.done(JSON.parse(text)) } catch (e) { proc.done({ ok: false, error: "bad backend output" }) } }
        }
    }
    Backend { id: weatherProc; onDone: d => root.weather = d }
    Backend { id: storageProc; onDone: d => { root.storage = d; if (d.measuring) storagePoll.restart() } }
    Backend { id: updaterProc; onDone: d => root.updater = d }
    Backend { id: netProc; onDone: d => root.net = d }
    Backend { id: vmProc; onDone: d => root.vms = d }
    Backend { id: bgUpdate; onDone: d => updaterProc.go(["updater"]) }
    PwObjectTracker { objects: [root.sink, root.source].concat(root.sinks).concat(root.sources).filter(n => !!n) }
    // background refresh of the updater cache (waybar badge reads the cache)
    Timer { interval: 30 * 60 * 1000; repeat: true; running: true; triggeredOnStart: true; onTriggered: bgUpdate.go(["bar-refresh"]) }
    Timer { interval: 5000; repeat: true; running: root.open && root.page === "constructs"; onTriggered: vmProc.go(["constructs"]) }
    Backend { id: dnsProc; onDone: d => root.dns = d }
    Backend { id: speedProc; onDone: d => root.speed = d }
    Backend { id: lastSpeed; onDone: d => { if (d.ok) root.speed = d } }
    Backend {
        id: actionProc
        property string after: ""
        onDone: d => { root.status = d.launched ? "Opened Ghostty: " + d.launched : (d.msg || ""); if (after) root.refresh(after) }
    }
    Timer { id: storagePoll; interval: 5000; onTriggered: if (root.open && root.page === "storage") storageProc.go(["storage"]) }
    Timer { interval: 10000; repeat: true; running: root.open && root.page === "network"; onTriggered: netProc.go(["network"]) }

    PanelWindow {
        id: win
        visible: root.open
        anchors { top: true; right: true }
        margins { top: 8; right: 12 }
        implicitWidth: 500
        implicitHeight: 720
        color: "transparent"
        WlrLayershell.namespace: "galaxy-hub"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Rectangle {
            id: card
            anchors.fill: parent
            radius: 22
            color: "transparent"
            focus: true
            Keys.onEscapePressed: { if (root.confirm) root.confirm = null; else root.open = false }
            opacity: root.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }

            Nebula { anchors.fill: parent; radius: card.radius; seed: 5 }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 16; spacing: 12

                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Text { text: "✦"; color: "#b46bff"; font.pixelSize: 16 }
                    Text { Layout.fillWidth: true; text: "G A L A X Y   H U B"; color: "#d4b8ff"; font.family: root.ui; font.pixelSize: 12 }
                    HubButton { text: "󰑐"; hint: "Refresh"; onClicked: root.refresh(root.page) }
                    HubButton { text: "×"; hint: "Close (Esc)"; onClicked: root.open = false }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: root.pages
                        HubButton {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.icon + " " + modelData.label; font.pixelSize: 11; hint: modelData.label
                            selected: root.page === modelData.id
                            onClicked: root.show(modelData.id)
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: "#26223a" }

                StackLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    currentIndex: ["weather", "storage", "updater", "constructs", "audio", "network"].indexOf(root.page)

                    // ── weather ──
                    ColumnLayout {
                        spacing: 12
                        Card {
                            Layout.fillWidth: true
                            RowLayout {
                                width: parent.width; spacing: 16
                                Text { text: root.weather.icon || "󰖐"; color: "#d4b8ff"; font.pixelSize: 56 }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    Text { text: root.weather.ok ? root.weather.temp + (root.weather.unit || "") : "--"; color: "#f2f0ff"; font.family: root.led; font.pixelSize: 40 }
                                    Text { text: root.weather.desc || (root.weather.error ? "Weather unavailable" : "Loading…"); color: "#b46bff"; font.family: root.ui; font.pixelSize: 14 }
                                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: "󰍎 " + (root.weather.location || "…"); color: "#9a96b3"; font.family: root.ui; font.pixelSize: 12 }
                                }
                            }
                        }
                        GridLayout {
                            Layout.fillWidth: true; columns: 4; columnSpacing: 8
                            Repeater {
                                model: [
                                    { k: "FEELS", v: root.weather.ok ? root.weather.feels + "°" : "--" },
                                    { k: "HUMID", v: root.weather.ok ? root.weather.humidity + "%" : "--" },
                                    { k: "WIND", v: root.weather.ok ? root.weather.wind + "" : "--" },
                                    { k: "SUN", v: root.weather.ok ? root.weather.sunset : "--" }
                                ]
                                Card {
                                    required property var modelData
                                    Layout.fillWidth: true; pad: 10
                                    Column {
                                        spacing: 4
                                        Text { text: modelData.k; color: "#5d5878"; font.family: root.ui; font.pixelSize: 10 }
                                        Text { text: modelData.v; color: "#d4b8ff"; font.family: root.led; font.pixelSize: 16 }
                                    }
                                }
                            }
                        }
                        Card {
                            Layout.fillWidth: true
                            Column {
                                width: parent.width; spacing: 8
                                Repeater {
                                    model: root.weather.days || []
                                    RowLayout {
                                        required property var modelData
                                        width: parent.width
                                        Text { Layout.preferredWidth: 44; text: modelData.label; color: "#9a96b3"; font.family: root.ui; font.pixelSize: 13 }
                                        Text { Layout.preferredWidth: 28; text: modelData.icon; color: "#b46bff"; font.pixelSize: 18 }
                                        Text { Layout.fillWidth: true; text: modelData.desc; color: "#f2f0ff"; font.family: root.ui; font.pixelSize: 12; elide: Text.ElideRight }
                                        Text { text: "󰖗 " + modelData.rain + "%"; color: "#6ee7f2"; font.family: root.ui; font.pixelSize: 11 }
                                        Text { Layout.preferredWidth: 72; horizontalAlignment: Text.AlignRight; text: modelData.hi + "° " + modelData.lo + "°"; color: "#d4b8ff"; font.family: root.led; font.pixelSize: 13 }
                                    }
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true; wrapMode: Text.Wrap
                            text: "Location: " + (root.weather.source || "…") + (root.weather.updated ? " · updated " + root.weather.updated : "") + "\nSet weather.city in ~/.config/quickshell/galaxy-hub/config.json"
                            color: "#5d5878"; font.family: root.ui; font.pixelSize: 10
                        }
                        Item { Layout.fillHeight: true }
                    }

                    // ── storage ──
                    ColumnLayout {
                        spacing: 12
                        Card {
                            Layout.fillWidth: true
                            ColumnLayout {
                                width: parent.width; spacing: 6
                                Text { text: "NIX STORE"; color: "#5d5878"; font.family: root.ui; font.pixelSize: 10 }
                                Text { text: root.storage.store || (root.storage.measuring ? "measuring…" : "--"); color: "#f2f0ff"; font.family: root.led; font.pixelSize: 34 }
                                Text { text: root.storage.measured ? "measured " + root.storage.measured + (root.storage.measuring ? " · re-measuring" : "") : "du -sb /nix/store runs in the background (niced)"; color: "#9a96b3"; font.family: root.ui; font.pixelSize: 11 }
                            }
                        }
                        Card {
                            Layout.fillWidth: true
                            ColumnLayout {
                                width: parent.width; spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { Layout.fillWidth: true; text: "󰋊  Disk (/)"; color: "#d4b8ff"; font.family: root.ui; font.pixelSize: 13 }
                                    Text { text: (root.storage.disk_free || "--") + " free of " + (root.storage.disk_total || "--"); color: "#9a96b3"; font.family: root.ui; font.pixelSize: 12 }
                                }
                                Rectangle {
                                    Layout.fillWidth: true; height: 8; radius: 4; color: "#26223a"
                                    Rectangle {
                                        width: parent.width * (root.storage.disk_used_pct || 0) / 100; height: parent.height; radius: 4
                                        gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#7c4dff" } GradientStop { position: 1; color: "#d4b8ff" } }
                                    }
                                }
                                Text { text: "󰁯  " + (root.storage.generations || 0) + " system generations · current #" + (root.storage.current_gen || "?"); color: "#f2f0ff"; font.family: root.ui; font.pixelSize: 12 }
                                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "auto GC: " + (root.storage.auto_gc || "--"); color: "#5d5878"; font.family: root.ui; font.pixelSize: 10 }
                            }
                        }
                        HubButton { Layout.fillWidth: true; primary: true; text: "󰨇  What's using space?  ·  Disk map"; onClicked: { Quickshell.execDetached({ command: ["/run/current-system/sw/bin/bash", "/home/r3dg0d/.local/bin/galaxy-disk"], environment: { HOME: "/home/r3dg0d", USER: "r3dg0d" } }); root.open = false } }
                        Text { text: "OPTIMIZE  ·  opens Ghostty, you type sudo"; color: "#5d5878"; font.family: root.ui; font.pixelSize: 10 }
                        HubButton { Layout.fillWidth: true; text: "󰃢  Collect garbage older than 14 days"; onClicked: root.ask("Collect garbage?", "Deletes system + user generations older than 14 days, then frees unreferenced store paths.\n\nsudo nix-collect-garbage --delete-older-than 14d", "gc-old") }
                        HubButton { Layout.fillWidth: true; danger: true; text: "󰩹  Delete ALL old generations"; onClicked: root.ask("Delete every old generation?", "Keeps only the current system. You can no longer roll back from the boot menu.\n\nsudo nix-collect-garbage -d", "gc-all", true) }
                        HubButton { Layout.fillWidth: true; text: "󰆼  Optimise store (hard-link duplicates)"; onClicked: root.ask("Optimise the Nix store?", "Hard-links identical files. Safe, but can take a while on a big store.\n\nsudo nix-store --optimise", "optimise") }
                        Item { Layout.fillHeight: true }
                    }

                    // ── updater ──
                    Flickable {
                        clip: true; contentHeight: updCol.implicitHeight; boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        ColumnLayout {
                            id: updCol
                            width: parent.width - 8; spacing: 10
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                HubButton { Layout.fillWidth: true; primary: true; text: "󰚰  Update everything"; onClicked: root.ask("Update everything?", "One Ghostty terminal, in order:\nsudo nix-channel --update && sudo nixos-rebuild switch\nnix profile upgrade --all\n(flatpak user+system and fwupdmgr update when installed)", "everything") }
                                HubButton { text: updaterProc.running ? "󰔟" : "󰑐"; hint: "Check again"; onClicked: updaterProc.go(["updater", "--refresh"]) }
                            }
                            Text { text: (root.updater.total || 0) + " pending  ·  checked " + (root.updater.checked || "…") + "  ·  refreshes every 30 min"; color: "#5d5878"; font.family: root.ui; font.pixelSize: 10 }

                            SectionHead { label: "KERNEL"; icon: "󰌽"; badge: root.updater.kernel && root.updater.kernel.reboot ? "reboot needed" : (root.updater.kernel && root.updater.kernel.candidate ? "new series " + root.updater.kernel.candidate : (root.updater.kernel && root.updater.kernel.update ? "update" : "")) }
                            Card {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    width: parent.width; spacing: 3
                                    readonly property var kn: root.updater.kernel || ({})
                                    KV { k: "running"; v: parent.kn.running || "--" }
                                    KV { k: "in system"; v: parent.kn.current || "--"; warn: !!parent.kn.reboot }
                                    KV { k: "latest " + (parent.kn.series || ""); v: parent.kn.latest || "unknown"; accent: !!parent.kn.update }
                                    KV { k: "nixpkgs newest"; v: parent.kn.nixpkgs_local ? (parent.kn.nixpkgs_local_version || parent.kn.nixpkgs_local) + "  (installed channel)" : "--"; accent: !!parent.kn.candidate }
                                    KV { visible: !!parent.kn.nixpkgs_channel && parent.kn.nixpkgs_channel !== parent.kn.nixpkgs_local; k: "next channel"; v: (parent.kn.nixpkgs_channel_version || "") }
                                    KV { k: "unstable"; v: parent.kn.nixpkgs_unstable ? (parent.kn.nixpkgs_unstable_version || parent.kn.nixpkgs_unstable) : "--" }
                                    KV { k: "kernel.org"; v: parent.kn.upstream_version || "--"; warn: !!parent.kn.upstream_ahead }
                                    Text { visible: !!parent.kn.upstream_ahead; Layout.fillWidth: true; wrapMode: Text.Wrap; text: "󰔟  kernel.org is ahead of nixpkgs, waiting for it to be packaged"; color: "#ffd479"; font.family: root.ui; font.pixelSize: 11 }
                                    Text { visible: !!parent.kn.reboot; text: "󰜉  booted kernel differs from /run/current-system, reboot to use it"; color: "#ffd479"; font.family: root.ui; font.pixelSize: 11 }
                                    Rectangle { visible: !!parent.kn.candidate; Layout.fillWidth: true; height: 1; color: "#26223a" }
                                    Text {
                                        visible: !!parent.kn.candidate; Layout.fillWidth: true; wrapMode: Text.Wrap; font.family: root.ui; font.pixelSize: 11
                                        text: !parent.kn.candidate ? "" : (parent.kn.check && parent.kn.check.series === parent.kn.candidate
                                              ? (parent.kn.check.ok ? "󰄬  NVIDIA " + parent.kn.nvidia + " builds on " + parent.kn.candidate + " (checked " + parent.kn.check.at + ")"
                                                                    : "󰅖  NVIDIA " + parent.kn.nvidia + " failed to build on " + parent.kn.candidate + " (" + parent.kn.check.at + ")")
                                              : "󰋗  NVIDIA " + parent.kn.nvidia + " not yet tested on " + parent.kn.candidate + " (" + (parent.kn.candidate_where || "") + ")")
                                        color: parent.kn.check && parent.kn.check.series === parent.kn.candidate ? (parent.kn.check.ok ? "#7dffa8" : "#ff5c8a") : "#9a96b3"
                                    }
                                    RowLayout {
                                        visible: !!parent.kn.candidate; Layout.fillWidth: true; spacing: 6
                                        HubButton { Layout.fillWidth: true; primary: true; text: "󰚰 Upgrade kernel to " + (parent.parent.kn.candidate || "")
                                            hint: "Build-check NVIDIA first, then nixos-rebuild boot (never switch)"
                                            onClicked: root.ask("Upgrade kernel to " + parent.parent.kn.candidate + "?", "One Ghostty terminal:\n1. checks nixpkgs has linux " + parent.parent.kn.candidate + "\n2. builds NVIDIA " + parent.parent.kn.nvidia + " against it\n3. only if that works: backs up " + parent.parent.kn.file + ", switches it, runs sudo nixos-rebuild boot\n\nNo switch: reboot when ready. The old generation stays in the boot menu; a failed rebuild restores the file.", "kernel-upgrade", false, parent.parent.kn.candidate) }
                                        HubButton { text: "󰙨"; hint: "Only test that NVIDIA builds (no changes)"; onClicked: root.act(["term", "kernel-check", parent.parent.kn.candidate]) }
                                    }
                                }
                            }

                            SectionHead { label: "NIXOS CHANNEL  " + (root.updater.channel || ""); icon: "󱄅"; badge: root.updater.update ? (root.updater.commits ? root.updater.commits + " commits" : "update") : "" }
                            Card {
                                Layout.fillWidth: true
                                border.color: root.updater.update ? "#7c4dff" : "#26223a"
                                ColumnLayout {
                                    width: parent.width; spacing: 3
                                    KV { k: "running"; v: root.updater.current || "--" }
                                    KV { k: "latest"; v: root.updater.latest || "--"; accent: !!root.updater.update }
                                    KV { k: "last switch"; v: root.updater.last_switch || "--" }
                                    Text { visible: !!root.updater.update && !!root.updater.current_rev; text: "<a href='https://github.com/NixOS/nixpkgs/compare/" + root.updater.current_rev + "..." + root.updater.latest_rev + "'>󰊢  view changes on GitHub</a>"; textFormat: Text.StyledText; linkColor: "#b46bff"; color: "#b46bff"; font.family: root.ui; font.pixelSize: 11; onLinkActivated: l => Qt.openUrlExternally(l) }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                HubButton { Layout.fillWidth: true; text: "󰚰 Update + switch"; onClicked: root.ask("Update and rebuild?", "sudo nix-channel --update && sudo nixos-rebuild switch", "upgrade") }
                                HubButton { Layout.fillWidth: true; text: "󰑓 Switch"; onClicked: root.ask("Rebuild now?", "sudo nixos-rebuild switch", "rebuild") }
                                HubButton { Layout.fillWidth: true; text: "󰙨 Diff"; hint: "Build against the latest channel, then nvd diff"; onClicked: root.ask("Preview package changes?", "Builds the system against the latest channel without switching, then:\nnix run nixpkgs#nvd -- diff /run/current-system ./result", "diff") }
                            }
                            Card {
                                Layout.fillWidth: true; visible: !!root.updater.nvd
                                ColumnLayout {
                                    width: parent.width; spacing: 4
                                    Text { text: "PACKAGE DIFF  ·  " + (root.updater.nvd_at || ""); color: "#5d5878"; font.family: root.ui; font.pixelSize: 10 }
                                    Text { Layout.fillWidth: true; text: root.updater.nvd || ""; wrapMode: Text.WrapAnywhere; maximumLineCount: 18; elide: Text.ElideRight; color: "#c8c2e0"; font.family: root.mono; font.pixelSize: 10 }
                                }
                            }

                            SectionHead { label: "FLAKES"; icon: "󱄅"; badge: { const n = (root.updater.flakes || []).filter(f => f.stale).length; return n ? n + " stale" : "" } }
                            Repeater {
                                model: root.updater.flakes || []
                                Card {
                                    required property var modelData
                                    Layout.fillWidth: true; pad: 10
                                    border.color: modelData.stale ? "#7c4dff" : "#26223a"
                                    ColumnLayout {
                                        width: parent.width; spacing: 3
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: modelData.name; color: "#f2f0ff"; font.family: root.ui; font.pixelSize: 13; elide: Text.ElideRight }
                                            Text { text: "oldest " + modelData.oldest + "d"; color: modelData.stale ? "#ffd479" : "#9a96b3"; font.family: root.led; font.pixelSize: 11 }
                                            HubButton { text: "󰚰 update"; hint: "nix flake update in " + modelData.path; onClicked: root.act(["term", "flake-update", modelData.path]) }
                                        }
                                        Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData.inputs.map(i => (i.stale ? "● " : "") + i.name + " " + i.age_days + "d").join("   "); color: "#5d5878"; font.family: root.mono; font.pixelSize: 10 }
                                    }
                                }
                            }
                            Text { visible: (root.updater.flakes || []).length === 0; text: "No flakes with a flake.lock found in ~/Projects, ~/.config or /etc/nixos."; color: "#5d5878"; font.family: root.ui; font.pixelSize: 11 }

                            SectionHead { label: "NIX PROFILE  ·  " + (root.updater.profile || []).length + " packages"; icon: "󰏗" }
                            Card {
                                Layout.fillWidth: true; pad: 10
                                ColumnLayout {
                                    width: parent.width; spacing: 2
                                    Repeater {
                                        model: root.updater.profile || []
                                        RowLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Text { Layout.preferredWidth: 130; text: modelData.name; color: "#f2f0ff"; font.family: root.ui; font.pixelSize: 11; elide: Text.ElideRight }
                                            Text { Layout.fillWidth: true; text: modelData.version; color: "#9a96b3"; font.family: root.mono; font.pixelSize: 10; elide: Text.ElideMiddle }
                                            Text { text: "󰚰"; color: profMouse.containsMouse ? "#d4b8ff" : "#5d5878"; font.pixelSize: 13
                                                MouseArea { id: profMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.act(["term", "profile-one", modelData.name]) } }
                                        }
                                    }
                                }
                            }
                            HubButton { Layout.fillWidth: true; text: "󰏗  Upgrade all profile packages (no sudo)"; onClicked: root.act(["term", "profile-all"]) }

                            SectionHead { label: "FLATPAK"; icon: "󰏖"; badge: root.updater.flatpak && root.updater.flatpak.present ? ((root.updater.flatpak.user.length + root.updater.flatpak.system.length) || "") + "" : "" }
                            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: !root.updater.flatpak ? "…" : !root.updater.flatpak.present ? "Flatpak isn't installed on this system." : ("user: " + (root.updater.flatpak.user.join(", ") || "up to date") + "\nsystem: " + (root.updater.flatpak.system.join(", ") || "up to date")); color: "#9a96b3"; font.family: root.ui; font.pixelSize: 11 }
                            SectionHead { label: "FIRMWARE"; icon: "󰍛"; badge: root.updater.firmware && root.updater.firmware.updates.length ? root.updater.firmware.updates.length + "" : "" }
                            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: !root.updater.firmware ? "…" : !root.updater.firmware.present ? "fwupd isn't installed. Staged: services.fwupd.enable in r3dg0d-widgets.nix." : (root.updater.firmware.updates.map(u => u.device + " → " + u.version).join("\n") || "No firmware updates."); color: "#9a96b3"; font.family: root.ui; font.pixelSize: 11 }
                        }
                    }

                    // ── constructs ──
                    Flickable {
                        clip: true; contentHeight: vmCol.implicitHeight; boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        ColumnLayout {
                            id: vmCol
                            width: parent.width - 8; spacing: 10
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Image { source: Quickshell.iconPath("galaxy-vm-construct"); sourceSize: Qt.size(40, 40); Layout.preferredWidth: 40; Layout.preferredHeight: 40 }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 1
                                    Text { text: "VM Construct"; color: "#f2f0ff"; font.family: root.ui; font.pixelSize: 16 }
                                    Text { text: "vmtools suite · checked " + (root.vms.checked || "…"); color: "#5d5878"; font.family: root.ui; font.pixelSize: 10 }
                                }
                                HubButton { text: "󰆍 manager"; hint: "VM Construct app (vmtools TUI: right-click the launcher)"; onClicked: { Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/quickshell/galaxy-vm/start.sh", "all"]); root.open = false } }
                                HubButton { text: "󰓙"; hint: "vmtools doctor"; onClicked: root.act(["term", "vm-doctor"]) }
                            }
                            Repeater {
                                model: root.vms.items || []
                                Card {
                                    required property var modelData
                                    Layout.fillWidth: true; pad: 12
                                    border.color: modelData.running > 0 ? "#7dffa8" : "#26223a"
                                    ColumnLayout {
                                        width: parent.width; spacing: 6
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 10
                                            Image { source: Quickshell.iconPath(modelData.icon); sourceSize: Qt.size(44, 44); Layout.preferredWidth: 44; Layout.preferredHeight: 44 }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 1
                                                Text { text: modelData.name; color: "#f2f0ff"; font.family: root.ui; font.pixelSize: 14 }
                                                Text { text: modelData.backend + "  ·  " + (modelData.vms.length ? modelData.running + "/" + modelData.vms.length + " running" : "no VMs yet"); color: "#9a96b3"; font.family: root.ui; font.pixelSize: 11 }
                                            }
                                            HubButton { text: "󰐊 open"; primary: true; hint: "Open the Construct app"; onClicked: { Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/quickshell/galaxy-vm/start.sh", ({ androidvm: "android", windowsvm: "windows", linuxvm: "linux", iosvm: "ios", macosvm: "macos" })[modelData.tool] || "all"]); root.open = false } }
                                            HubButton { visible: modelData.tool === "windowsvm" || modelData.tool === "linuxvm"; text: "󰍹"; hint: "virt-manager"; onClicked: root.act(["term", "vm-gui", modelData.tool]) }
                                        }
                                        Repeater {
                                            model: modelData.vms
                                            RowLayout {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Rectangle { width: 7; height: 7; radius: 4; color: modelData.state.toLowerCase().indexOf("running") >= 0 ? "#7dffa8" : "#5d5878" }
                                                Text { Layout.fillWidth: true; text: modelData.name; color: "#f2f0ff"; font.family: root.mono; font.pixelSize: 11 }
                                                Text { text: modelData.state; color: "#9a96b3"; font.family: root.ui; font.pixelSize: 11 }
                                            }
                                        }
                                        Text { visible: modelData.note.length > 0; Layout.fillWidth: true; wrapMode: Text.Wrap; text: "󰀦  " + modelData.note; color: "#ffd479"; font.family: root.ui; font.pixelSize: 11 }
                                        HubButton { visible: modelData.tool === "androidvm" && modelData.note.length > 0; text: "󰒓  androidvm setup"; onClicked: root.act(["term", "android-setup"]) }
                                    }
                                }
                            }
                            SectionHead { visible: (root.vms.doctor_fails || []).length > 0; label: "HOST CHECKS"; icon: "󰓙"; badge: (root.vms.doctor_fails || []).length + " failing" }
                            Repeater {
                                model: root.vms.doctor_fails || []
                                Text { required property var modelData; Layout.fillWidth: true; wrapMode: Text.Wrap; text: "✗ " + modelData.replace(/\s{2,}/g, " · "); color: "#ff7aa2"; font.family: root.mono; font.pixelSize: 10 }
                            }
                            Text { visible: (root.vms.doctor_fails || []).some(f => f.indexOf("group") >= 0); Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Group fixes (libvirtd, kvm) are staged in ~/rice-staging/r3dg0d-widgets.nix; they need a rebuild and a re-login."; color: "#5d5878"; font.family: root.ui; font.pixelSize: 10 }
                        }
                    }

                    // ── audio ──
                    Flickable {
                        clip: true; contentHeight: audioCol.implicitHeight; boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                    ColumnLayout {
                        id: audioCol
                        width: parent.width - 8; spacing: 10
                        SectionHead { label: "OUTPUT"; icon: "󰕾" }
                        Card {
                            Layout.fillWidth: true
                            ColumnLayout {
                                width: parent.width; spacing: 8
                                Text { Layout.fillWidth: true; elide: Text.ElideRight; text: root.nodeName(root.sink); color: "#f2f0ff"; font.family: root.ui; font.pixelSize: 13 }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 10
                                    HubButton { text: root.sink && root.sink.audio && root.sink.audio.muted ? "󰝟" : "󰕾"; selected: !!(root.sink && root.sink.audio && root.sink.audio.muted); hint: "Mute output"; onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted }
                                    GalaxySlider { Layout.fillWidth: true; enabled: !!(root.sink && root.sink.audio); value: root.sink && root.sink.audio ? root.sink.audio.volume : 0; onMoved: root.sink.audio.volume = value; dim: !!(root.sink && root.sink.audio && root.sink.audio.muted) }
                                    Text { Layout.preferredWidth: 46; horizontalAlignment: Text.AlignRight; text: root.sink && root.sink.audio ? Math.round(root.sink.audio.volume * 100) + "%" : "--"; color: "#d4b8ff"; font.family: root.led; font.pixelSize: 14 }
                                }
                            }
                        }
                        Repeater {
                            model: root.sinks
                            DeviceRow { required property var modelData; node: modelData; current: root.sink === modelData; onPicked: Pipewire.preferredDefaultAudioSink = modelData }
                        }
                        SectionHead { label: "MICROPHONE"; icon: "󰍬"; Layout.topMargin: 6 }
                        Card {
                            Layout.fillWidth: true
                            ColumnLayout {
                                width: parent.width; spacing: 8
                                Text { Layout.fillWidth: true; elide: Text.ElideRight; text: root.nodeName(root.source); color: "#f2f0ff"; font.family: root.ui; font.pixelSize: 13 }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 10
                                    HubButton { text: root.source && root.source.audio && root.source.audio.muted ? "󰍭" : "󰍬"; selected: !!(root.source && root.source.audio && root.source.audio.muted); hint: "Mute mic"; onClicked: if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted }
                                    GalaxySlider { Layout.fillWidth: true; enabled: !!(root.source && root.source.audio); value: root.source && root.source.audio ? root.source.audio.volume : 0; onMoved: root.source.audio.volume = value; dim: !!(root.source && root.source.audio && root.source.audio.muted) }
                                    Text { Layout.preferredWidth: 46; horizontalAlignment: Text.AlignRight; text: root.source && root.source.audio ? Math.round(root.source.audio.volume * 100) + "%" : "--"; color: "#d4b8ff"; font.family: root.led; font.pixelSize: 14 }
                                }
                            }
                        }
                        Repeater {
                            model: root.sources
                            DeviceRow { required property var modelData; node: modelData; current: root.source === modelData; mic: true; onPicked: Pipewire.preferredDefaultAudioSource = modelData }
                        }
                        HubButton { Layout.fillWidth: true; text: "󰒓  pavucontrol (per-app volume)"; onClicked: Quickshell.execDetached(["pavucontrol"]) }
                    }
                    }

                    // ── network ──
                    Flickable {
                        clip: true; contentHeight: netCol.implicitHeight; boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        ColumnLayout {
                            id: netCol
                            width: parent.width - 8; spacing: 10
                            Card {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    width: parent.width; spacing: 4
                                    Repeater {
                                        model: root.net.devices || []
                                        RowLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Text { text: modelData.type === "ethernet" ? "󰈀" : modelData.type === "wifi" ? "󰤨" : modelData.type === "wireguard" ? "󰦝" : "󰛳"; color: modelData.state.indexOf("connected") === 0 ? "#b46bff" : "#5d5878"; font.pixelSize: 16 }
                                            Text { Layout.fillWidth: true; text: modelData.device + (modelData.connection ? "  ·  " + modelData.connection : ""); color: "#f2f0ff"; font.family: root.ui; font.pixelSize: 12; elide: Text.ElideRight }
                                            Text { text: modelData.state; color: modelData.state.indexOf("connected") === 0 ? "#7dffa8" : "#5d5878"; font.family: root.ui; font.pixelSize: 11 }
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { Layout.fillWidth: true; text: "󰤨  WI-FI"; color: "#d4b8ff"; font.family: root.ui; font.pixelSize: 12 }
                                HubButton { text: root.net.wifi_on ? "on" : "off"; selected: !!root.net.wifi_on; onClicked: root.act(["wifi", root.net.wifi_on ? "off" : "on"], "network") }
                                HubButton { text: "󰒓"; hint: "Connection editor"; onClicked: root.act(["editor"]) }
                            }
                            Repeater {
                                model: root.net.networks || []
                                Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true; height: 36; radius: 10
                                    color: wifiMouse.containsMouse ? "#1a1630" : "#0b0914"
                                    border.color: modelData.active ? "#b46bff" : "#26223a"
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                                        Text { text: modelData.signal > 75 ? "󰤨" : modelData.signal > 50 ? "󰤥" : modelData.signal > 25 ? "󰤢" : "󰤟"; color: "#b46bff"; font.pixelSize: 15 }
                                        Text { Layout.fillWidth: true; text: modelData.ssid; color: "#f2f0ff"; font.family: root.ui; font.pixelSize: 12; elide: Text.ElideRight }
                                        Text { text: (modelData.known ? "󰄬 " : "") + (modelData.security === "open" ? "open" : "󰌾"); color: "#9a96b3"; font.family: root.ui; font.pixelSize: 11 }
                                        Text { text: modelData.signal + "%"; color: "#d4b8ff"; font.family: root.led; font.pixelSize: 11 }
                                    }
                                    MouseArea {
                                        id: wifiMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.active) root.act(["wifi-down", modelData.ssid], "network")
                                            else if (modelData.known || modelData.security === "open") { root.status = "Connecting to " + modelData.ssid + "…"; root.act(["wifi-connect", modelData.ssid], "network") }
                                            else root.act(["term", "wifi-ask", modelData.ssid])
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; Layout.topMargin: 6
                                Text { Layout.fillWidth: true; text: "󰂯  BLUETOOTH"; color: "#d4b8ff"; font.family: root.ui; font.pixelSize: 12 }
                                HubButton { text: root.net.bt_on ? "on" : "off"; selected: !!root.net.bt_on; enabled: !!root.net.bt_present; onClicked: root.act(["bt-power", root.net.bt_on ? "off" : "on"], "network") }
                            }
                            Text { visible: !!root.net.bt_on && (root.net.bt_devices || []).length === 0; text: "No paired devices. Pair with bluetoothctl."; color: "#5d5878"; font.family: root.ui; font.pixelSize: 11 }
                            Repeater {
                                model: root.net.bt_devices || []
                                RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Text { text: "󰂱"; color: modelData.connected ? "#b46bff" : "#5d5878"; font.pixelSize: 15 }
                                    Text { Layout.fillWidth: true; text: modelData.name; color: "#f2f0ff"; font.family: root.ui; font.pixelSize: 12; elide: Text.ElideRight }
                                    HubButton { text: modelData.connected ? "disconnect" : "connect"; onClicked: root.act([modelData.connected ? "bt-disconnect" : "bt-connect", modelData.mac], "network") }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; Layout.topMargin: 6; spacing: 8
                                HubButton { Layout.fillWidth: true; text: speedProc.running ? "󰔟  testing…" : "󰓅  Speedtest"; enabled: !speedProc.running; onClicked: speedProc.go(["speedtest"]) }
                                HubButton { Layout.fillWidth: true; text: dnsProc.running ? "󰔟  checking…" : "󰇖  DNS check"; enabled: !dnsProc.running; onClicked: dnsProc.go(["dns"]) }
                            }
                            Card {
                                Layout.fillWidth: true; visible: root.speed.ok !== undefined
                                ColumnLayout {
                                    width: parent.width; spacing: 4
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { Layout.fillWidth: true; text: "󰇚 " + (root.speed.down ?? "--"); color: "#f2f0ff"; font.family: root.led; font.pixelSize: 18 }
                                        Text { Layout.fillWidth: true; text: "󰕒 " + (root.speed.up ?? "--"); color: "#d4b8ff"; font.family: root.led; font.pixelSize: 18 }
                                        Text { text: (root.speed.ping ?? "--") + " ms"; color: "#b46bff"; font.family: root.led; font.pixelSize: 14 }
                                    }
                                    Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.speed.ok ? "Mbit/s · " + root.speed.server + " · " + root.speed.at + " · via " + root.speed.via : (root.speed.error || ""); color: "#5d5878"; font.family: root.ui; font.pixelSize: 10 }
                                }
                            }
                            Card {
                                Layout.fillWidth: true; visible: root.dns.servers !== undefined
                                ColumnLayout {
                                    width: parent.width; spacing: 4
                                    Text { text: (root.dns.ok ? "󰄬 resolving" : "󰅖 lookup failures") + (root.dns.mullvad ? "  ·  Mullvad " + root.dns.exit : "  ·  not on Mullvad"); color: root.dns.ok ? "#7dffa8" : "#ff5c8a"; font.family: root.ui; font.pixelSize: 12 }
                                    Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "resolvers  " + (root.dns.servers || []).join("  "); color: "#9a96b3"; font.family: root.mono; font.pixelSize: 11 }
                                    Repeater {
                                        model: root.dns.tests || []
                                        RowLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: modelData.host; color: "#f2f0ff"; font.family: root.mono; font.pixelSize: 11 }
                                            Text { text: modelData.ok ? modelData.ms + " ms" : "fail"; color: modelData.ok ? (modelData.ms < 150 ? "#7dffa8" : "#ffd479") : "#ff5c8a"; font.family: root.led; font.pixelSize: 11 }
                                        }
                                    }
                                    Text { visible: !!root.dns.resolver_seen; text: "upstream resolver seen by Google  " + (root.dns.resolver_seen || ""); color: "#5d5878"; font.family: root.mono; font.pixelSize: 10 }
                                }
                            }
                        }
                    }
                }

                Text { Layout.fillWidth: true; visible: root.status.length > 0; text: root.status; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; color: "#9a96b3"; font.family: root.ui; font.pixelSize: 11 }
            }

            // confirmation overlay
            Rectangle {
                anchors.fill: parent; radius: card.radius; color: "#d907060d"
                visible: !!root.confirm
                MouseArea { anchors.fill: parent }
                Rectangle {
                    anchors.centerIn: parent; width: parent.width - 48; height: confirmCol.implicitHeight + 36; radius: 18
                    color: "#0f0d1a"; border.color: root.confirm && root.confirm.danger ? "#ff5c8a" : "#b46bff"
                    ColumnLayout {
                        id: confirmCol
                        anchors.fill: parent; anchors.margins: 18; spacing: 12
                        Text { text: root.confirm ? root.confirm.title : ""; color: "#f2f0ff"; font.family: root.ui; font.pixelSize: 17 }
                        Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.confirm ? root.confirm.text : ""; color: "#9a96b3"; font.family: root.mono; font.pixelSize: 12 }
                        Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Runs in a Ghostty window. You type your sudo password there; nothing is stored."; color: "#5d5878"; font.family: root.ui; font.pixelSize: 10 }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            HubButton { Layout.fillWidth: true; text: "Cancel"; onClicked: root.confirm = null }
                            HubButton { Layout.fillWidth: true; primary: !(root.confirm && root.confirm.danger); danger: !!(root.confirm && root.confirm.danger); text: "Run"; onClicked: { const k = root.confirm.key; const x = root.confirm.extra; root.confirm = null; root.act(x ? ["term", k, x] : ["term", k]) } }
                        }
                    }
                }
            }
        }
    }
}
