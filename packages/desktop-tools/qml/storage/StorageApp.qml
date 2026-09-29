import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.shared

// Full Storage Optimizer UI: analysis, Safe Clean (scan → estimate → select →
// confirm → clean → rescan → measured result) and Large Items review.
Item {
    id: app
    property string startPage: "overview"
    property string page: startPage === "clean" ? "clean" : startPage === "items" ? "items" : "overview"
    function showPage(p) { page = p === "clean" ? "clean" : p === "items" ? "items" : "overview"; }

    readonly property var sc: StorageState.scan
    readonly property var cats: sc.categories || []
    readonly property var safe: (sc.safeClean || {}).items || []
    readonly property var fsList: sc.filesystems || (StorageState.summary.filesystems || [])
    readonly property var h: StorageState.home

    property var sel: ({})
    function resetSel() {
        const s = {};
        for (const it of safe) s[it.id] = !!(it.available && it["default"]);
        sel = s;
    }
    onSafeChanged: resetSel()
    readonly property var chosen: safe.filter(i => i.available && sel[i.id])
    readonly property real chosenBytes: chosen.reduce((a, i) => a + (i.estimate || 0), 0)

    Component.onCompleted: {
        resetSel();
        const hrs = StorageState.summary.rescanOnOpenAfterHours || 0;
        const last = StorageState.lastScan;
        if (hrs > 0 && (!last || last.ageHours >= hrs)) StorageState.startScan();
    }

    Rectangle { anchors.fill: parent; color: Theme.background }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        // ---------------------------------------------------------- header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Icon { icon: Theme.iHdd; size: 26 }
            ColumnLayout {
                spacing: 2
                Label { text: "Storage Optimizer"; font.pixelSize: Theme.fsHuge; font.bold: true }
                Label {
                    color: Theme.fgDim
                    text: StorageState.hasScan ? "Last analyzed " + Theme.ago(app.sc.finishedAt) + " in " + ((app.sc.durationMs || 0) / 1000).toFixed(1) + " s"
                                               : "Not analyzed yet. Nothing is scanned in the background."
                }
            }
            Item { Layout.fillWidth: true }
            Btn {
                icon: StorageState.scanning ? Theme.iX : Theme.iSync
                text: StorageState.scanning ? "Cancel scan" : "Analyze"
                kind: StorageState.scanning ? "danger" : "normal"
                enabled: !StorageState.cleaning
                onClicked: StorageState.scanning ? StorageState.cancelScan() : StorageState.startScan()
            }
        }

        // ---------------------------------------------------------- totals
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Stat { title: "Total storage"; value: Theme.bytes(app.h.size); sub: "home filesystem" }
            Stat { title: "Used"; value: Theme.bytes(app.h.used); sub: (app.h.percent || 0) + "%" }
            Stat { title: "Free"; value: Theme.bytes(app.h.avail); sub: "available to you"; accent: (app.h.percent || 0) >= 90 ? Theme.warning : Theme.primary }
            Stat {
                title: "Potential safe cleanup"
                value: StorageState.hasScan ? Theme.bytes((app.sc.safeClean || {}).totalEstimate) : "—"
                sub: StorageState.hasScan ? Theme.bytes((app.sc.safeClean || {}).defaultEstimate) + " selected by default" : "analyze first"
                accent: Theme.tertiary
            }
        }
        Bar { Layout.fillWidth: true; value: (app.h.percent || 0) / 100; implicitHeight: 8 }

        // scan progress
        Surface {
            visible: StorageState.scanning || (StorageState.scanMessage !== "" && !StorageState.scanOk)
            Layout.fillWidth: true
            implicitHeight: 44
            halftone: false
            borderColor: StorageState.scanOk ? Theme.tertiary : Theme.error
            Indeterminate {
                visible: StorageState.scanning
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
                implicitHeight: 3
                barColor: Theme.tertiary
            }
            RowLayout {
                anchors.fill: parent; anchors.margins: 12; spacing: 10
                Spinner { visible: StorageState.scanning; size: 16 }
                Label {
                    Layout.fillWidth: true
                    color: StorageState.scanning ? Theme.fg : Theme.error
                    text: StorageState.scanning
                        ? (StorageState.progress.phase || "Scanning") + " — " + Theme.bytes(StorageState.progress.bytes || 0) + " in "
                          + (StorageState.progress.files || 0).toLocaleString() + " files · " + (StorageState.progress.area || "")
                        : StorageState.scanMessage
                    elide: Text.ElideMiddle
                }
            }
        }

        // ---------------------------------------------------------- tabs
        RowLayout {
            spacing: 6
            Tab { text: "Overview"; key: "overview" }
            Tab { text: "Safe Clean"; key: "clean" }
            Tab { text: "Large Items"; key: "items" }
            Item { Layout.fillWidth: true }
            Label {
                visible: (app.sc.warnings || []).length > 0
                text: "⚠ " + (app.sc.warnings || []).length + " scan note(s) — see Overview"
                color: Theme.warning
            }
        }

        // ---------------------------------------------------------- overview
        ScrollView {
            visible: app.page === "overview"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                width: parent.width
                spacing: 14
                Card {
                    Layout.fillWidth: true
                    icon: Theme.iList; title: "Storage by category"
                    chip: StorageState.hasScan ? "measured" : "not analyzed"
                    Label { visible: !StorageState.hasScan; text: "Press Analyze to measure categories."; color: Theme.fgDim }
                    Repeater {
                        model: app.cats
                        ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 3
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: modelData.label; font.bold: true; Layout.preferredWidth: 170 }
                                Label { text: modelData.description; color: Theme.fgDim; Layout.fillWidth: true; font.pixelSize: Theme.fsSmall }
                                Label { text: Theme.bytes(modelData.bytes); font.bold: true; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 90 }
                            }
                            Bar {
                                Layout.fillWidth: true
                                value: app.cats.length ? modelData.bytes / Math.max(1, app.cats[0].bytes) : 0
                                barColor: ["ai-models", "gaming", "vms"].indexOf(modelData.id) >= 0 ? Theme.tertiary : Theme.primary
                            }
                        }
                    }
                    Label {
                        visible: StorageState.hasScan
                        text: "Sizes are allocated disk blocks; hard links and bind mounts are counted once. Nix is measured from store metadata, containers from Docker."
                        color: Theme.fgDim; font.pixelSize: Theme.fsSmall; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
                Card {
                    Layout.fillWidth: true
                    icon: Theme.iDisk; title: "Filesystems"
                    Repeater {
                        model: app.fsList
                        KV {
                            required property var modelData
                            k: modelData.mount + " (" + modelData.fstype + ")"
                            v: Theme.bytes(modelData.used) + " used of " + Theme.bytes(modelData.size) + " · " + Theme.bytes(modelData.avail) + " free (" + modelData.percent + "%)"
                        }
                    }
                }
                Card {
                    visible: (app.sc.warnings || []).length > 0
                    Layout.fillWidth: true
                    icon: Theme.iAlert; title: "Scan notes"
                    Repeater {
                        model: app.sc.warnings || []
                        Label { required property string modelData; text: "• " + modelData; color: Theme.warning; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    }
                }
                Card {
                    Layout.fillWidth: true
                    icon: Theme.iShield; title: "Protected data"
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.fgDim
                        text: "Never cleaned automatically and never offered for deletion: Documents, Pictures, Music, Videos and Desktop (XDG), your Obsidian vault, Git repositories, SSH/GPG/password stores, browser profiles, VM disks, games, Proton prefixes and saves, and AI models/datasets. Large Items only shows them so you can review them; Hugging Face and Ollama models should be removed with their own tools."
                    }
                }
            }
        }

        // ---------------------------------------------------------- safe clean
        ColumnLayout {
            visible: app.page === "clean"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            Label {
                visible: !StorageState.hasScan
                text: "Analyze first — Safe Clean estimates come from the latest scan."
                color: Theme.fgDim
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                ColumnLayout {
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: app.safe
                        Surface {
                            id: row
                            required property var modelData
                            property bool open: false
                            Layout.fillWidth: true
                            implicitHeight: rc.implicitHeight + 20
                            halftone: false
                            borderColor: app.sel[modelData.id] ? Theme.primary : Theme.border
                            opacity: modelData.available ? 1 : 0.55
                            ColumnLayout {
                                id: rc
                                x: 12; y: 10
                                width: parent.width - 24
                                spacing: 4
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Check {
                                        enabled: modelData.available && !StorageState.cleaning
                                        checked: !!app.sel[modelData.id]
                                        onToggled: v => { const s = Object.assign({}, app.sel); s[modelData.id] = v; app.sel = s; }
                                    }
                                    Label { text: modelData.label; font.bold: true; Layout.fillWidth: true }
                                    Chip { visible: !!modelData.requiresAuth; text: "needs authentication"; tone: "warn" }
                                    Chip { text: modelData.estimateKind; tone: modelData.estimateKind === "measured" ? "ok" : "info" }
                                    Label {
                                        text: modelData.available ? Theme.bytes(modelData.estimate) : "nothing to clean"
                                        font.bold: true; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 150
                                        color: modelData.available ? Theme.primary : Theme.fgDim
                                    }
                                }
                                Label { text: modelData.description; color: Theme.fgDim; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                Label { visible: !!modelData.measuredBy; text: "Measured by: " + (modelData.measuredBy || ""); color: Theme.fgDim; font.pixelSize: Theme.fsSmall; Layout.fillWidth: true }
                                Btn {
                                    visible: modelData.available
                                    text: row.open ? "Hide details" : "Show exactly what is removed"
                                    icon: row.open ? Theme.iCaretDown : Theme.iCaretRight
                                    onClicked: row.open = !row.open
                                }
                                Label {
                                    visible: row.open
                                    Layout.fillWidth: true
                                    wrapMode: Text.WrapAnywhere
                                    font.family: Theme.mono
                                    font.pixelSize: 12
                                    color: Theme.fgDim
                                    text: app.detailText(modelData)
                                    maximumLineCount: 40
                                }
                            }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: app.chosen.length + " categor" + (app.chosen.length === 1 ? "y" : "ies") + " selected · estimated " + Theme.bytes(app.chosenBytes)
                    font.bold: true; Layout.fillWidth: true
                }
                Btn { text: "Reset to defaults"; onClicked: app.resetSel(); enabled: !StorageState.cleaning }
                Btn {
                    text: StorageState.cleaning ? "Cleaning…" : "Clean selected…"; icon: Theme.iBroom; kind: "primary"
                    busy: StorageState.cleaning
                    enabled: app.chosen.length > 0 && !StorageState.scanning && !StorageState.cleaning && StorageState.hasScan
                    onClicked: confirmClean.visible = true
                }
            }
        }

        // ---------------------------------------------------------- large items
        ColumnLayout {
            visible: app.page === "items"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            property string filter: "All"
            property bool showIgnored: false
            id: itemsPage
            readonly property var classes: ["All"].concat([...new Set((app.sc.largeItems || []).map(i => i.classification))])
            readonly property var rows: (app.sc.largeItems || []).filter(i =>
                (itemsPage.filter === "All" || i.classification === itemsPage.filter) && (itemsPage.showIgnored || !i.ignored))
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: itemsPage.classes
                    Btn {
                        required property string modelData
                        text: modelData
                        kind: itemsPage.filter === modelData ? "primary" : "normal"
                        implicitHeight: 28
                        onClicked: itemsPage.filter = modelData
                    }
                }
                Item { Layout.fillWidth: true }
                Check { text: "Show ignored"; checked: itemsPage.showIgnored; onToggled: v => itemsPage.showIgnored = v }
            }
            Label {
                text: "Items of at least " + Theme.bytes(app.sc.thresholdBytes) + ". This is a review list, not Safe Clean: nothing here is deleted automatically."
                color: Theme.fgDim; Layout.fillWidth: true; wrapMode: Text.WordWrap
            }
            Label {
                visible: StorageState.actionMessage !== ""
                text: StorageState.actionMessage
                color: StorageState.actionOk ? Theme.ok : Theme.error
                Layout.fillWidth: true; wrapMode: Text.WordWrap
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: itemsPage.rows
                ScrollBar.vertical: ScrollBar {}
                delegate: Surface {
                    required property var modelData
                    width: ListView.view.width - 12
                    height: 64
                    halftone: false
                    opacity: modelData.ignored ? 0.5 : 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 12
                        Label { text: Theme.bytes(modelData.bytes); font.bold: true; font.pixelSize: Theme.fsBig; Layout.preferredWidth: 90; color: Theme.primary }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            RowLayout {
                                spacing: 8
                                Label { text: modelData.name; font.bold: true; Layout.maximumWidth: 380 }
                                Chip { text: modelData.classification; tone: modelData.classification === "Reproducible Build" || modelData.classification === "Cache" ? "info" : "muted" }
                                Chip { visible: !!modelData.protected; text: "protected"; tone: "warn" }
                                Label { text: modelData.category + " · modified " + Theme.date(modelData.modified); color: Theme.fgDim; font.pixelSize: Theme.fsSmall }
                            }
                            Label { text: modelData.path; font.family: Theme.mono; font.pixelSize: 12; color: Theme.fgDim; Layout.fillWidth: true; elide: Text.ElideMiddle }
                        }
                        Btn { text: "Open"; implicitHeight: 28; onClicked: StorageState.openPath(modelData.path) }
                        Btn { text: "Folder"; icon: Theme.iFolder; implicitHeight: 28; onClicked: StorageState.openFolder(modelData.path) }
                        Btn { text: "Inspect"; icon: Theme.iInfo; implicitHeight: 28; onClicked: { inspect.item = modelData; inspect.visible = true; } }
                        Btn {
                            text: modelData.ignored ? "Unignore" : "Ignore"; implicitHeight: 28
                            onClicked: StorageState.setIgnored(modelData.path, !modelData.ignored)
                        }
                        Btn {
                            visible: !!modelData.trashable
                            text: "Trash…"; icon: Theme.iTrash; kind: "danger"; implicitHeight: 28
                            onClicked: { trashConfirm.item = modelData; trashConfirm.visible = true; }
                        }
                    }
                }
            }
        }
    }

    function detailText(it) {
        const d = it.details;
        switch (it.id) {
        case "nix-generations": {
            const del = (d || []).filter(g => !g.keep).map(g => g.generation + " (" + Theme.date(g.date) + ")");
            const keep = (d || []).filter(g => g.keep).map(g => g.generation + " — " + g.reason);
            const ud = (it.userDetails || []).filter(g => !g.keep).map(g => g.generation);
            return "Delete system generations:\n  " + (del.join(", ") || "none") + "\nKeep:\n  " + keep.join("\n  ")
                 + "\nDelete user-profile generations: " + (ud.join(", ") || "none")
                 + "\nThen: nix-store --gc, and switch-to-configuration boot to drop their boot entries.";
        }
        case "flatpak-unused":
            return "user:   " + ((d || {}).user || []).join(", ") + "\nsystem: " + ((d || {}).system || []).join(", ");
        case "package-caches":
            return (d || []).map(x => x.tool + "  " + Theme.bytes(x.bytes) + "  " + x.path).join("\n");
        case "containers":
            return "Dangling images:\n  " + ((d || {}).danglingImages || []).map(x => x.image + "  " + Theme.bytes(x.bytes)).join("\n  ")
                 + "\nBuild cache reclaimable: " + Theme.bytes((d || {}).buildCacheReclaimable);
        default:
            return it.description;
        }
    }

    // ============================================================ modals
    Modal {
        id: confirmClean
        panelWidth: 640
        panelHeight: 460
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10
            Label { text: "Confirm Safe Clean"; font.pixelSize: Theme.fsBig + 2; font.bold: true }
            Label {
                text: "The following Safe Clean categories will be removed. Personal files, projects, photos, videos, saves, models, datasets, VM disks and git repos are never touched. Afterwards the disk is rescanned and the actual reclaimed space is reported."
                color: Theme.fgDim; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            Repeater {
                model: app.chosen
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Icon { icon: Theme.iBroom; size: 14 }
                    Label { text: modelData.label; Layout.fillWidth: true }
                    Chip { visible: !!modelData.requiresAuth; text: "authentication"; tone: "warn" }
                    Label { text: Theme.bytes(modelData.estimate); font.bold: true }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
            RowLayout {
                Label { text: "Estimated total"; Layout.fillWidth: true; font.bold: true }
                Label { text: Theme.bytes(app.chosenBytes); font.bold: true; color: Theme.primary }
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Btn { text: "Cancel"; onClicked: confirmClean.visible = false }
                Btn {
                    text: "Clean now"; kind: "danger"; icon: Theme.iBroom
                    onClicked: {
                        confirmClean.visible = false;
                        cleanLog.clear();
                        cleanRun.order = app.chosen.map(i => i.id);
                        cleanRun.labels = app.chosen.reduce((m, i) => { m[i.id] = i.label; return m; }, {});
                        cleanRun.visible = true;
                        StorageState.startClean(cleanRun.order);
                    }
                }
            }
        }
    }

    Connections {
        target: StorageState
        function onCleanLog(line) { cleanLog.append(line); }
    }
    Modal {
        id: cleanRun
        property var order: []
        property var labels: ({})
        property bool showLog: false
        panelWidth: 860
        panelHeight: showLog ? 680 : 440
        readonly property var r: StorageState.cleanResult
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10
            RowLayout {
                Spinner { visible: StorageState.cleaning; size: 22 }
                Icon { visible: !StorageState.cleaning && !!cleanRun.r; icon: cleanRun.r && cleanRun.r.ok ? Theme.iCheck : Theme.iAlert; color: cleanRun.r && cleanRun.r.ok ? Theme.ok : Theme.error; size: 22 }
                Label { text: StorageState.cleaning ? StorageState.cleanPhase : (cleanRun.r ? cleanRun.r.message : ""); font.pixelSize: Theme.fsBig + 2; font.bold: true; Layout.fillWidth: true }
            }
            Indeterminate {
                visible: StorageState.cleaning
                Layout.fillWidth: true
                barColor: StorageState.authState === "waiting" ? Theme.warning : Theme.primary
            }
            AuthBanner {
                Layout.fillWidth: true
                state: StorageState.authState
                message: StorageState.authMessage
            }
            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: StorageState.cleaning
                        ? ("Cleaning… " + (StorageState.cleanDurationText || ""))
                        : (StorageState.cleanDurationText ? ("Duration " + StorageState.cleanDurationText) : "")
                    color: Theme.fgDim; font.family: Theme.mono; font.pixelSize: Theme.fsSmall
                    Layout.fillWidth: true
                }
            }
            Repeater {
                model: cleanRun.order
                RowLayout {
                    required property string modelData
                    readonly property string status: StorageState.cleanSteps[modelData] || "pending"
                    Spinner { visible: status === "running"; size: 14 }
                    Icon {
                        visible: status !== "running"; size: 14
                        icon: status === "ok" ? Theme.iCheck : status === "failed" || status === "skipped" ? Theme.iX : Theme.iCaretRight
                        color: status === "ok" ? Theme.ok : status === "failed" ? Theme.error : status === "skipped" ? Theme.warning : Theme.fgDim
                    }
                    Label { text: cleanRun.labels[modelData] || modelData; Layout.fillWidth: true }
                    Label { text: status; color: Theme.fgDim }
                }
            }
            GridLayout {
                visible: !!cleanRun.r && cleanRun.r.reclaimedBytes !== undefined
                columns: 2; columnSpacing: 16
                Label { text: "Reclaimed (measured)"; color: Theme.fgDim }
                Label { text: Theme.bytes(cleanRun.r ? cleanRun.r.reclaimedBytes : 0); font.bold: true; color: Theme.primary; font.pixelSize: Theme.fsBig }
                Label { text: "Estimated"; color: Theme.fgDim }
                Label { text: Theme.bytes(cleanRun.r ? cleanRun.r.estimatedBytes : 0) }
                Label { text: "Filesystem change"; color: Theme.fgDim }
                Label { text: Theme.bytes(cleanRun.r ? cleanRun.r.filesystemDelta : 0) + " more free space (includes other disk activity)"; color: Theme.fgDim }
                Label { text: "Measured by"; color: Theme.fgDim }
                Label { text: cleanRun.r ? (cleanRun.r.measuredBy || "") : ""; color: Theme.fgDim }
            }
            LogView { id: cleanLog; visible: cleanRun.showLog; Layout.fillWidth: true; Layout.fillHeight: true }
            Item { visible: !cleanRun.showLog; Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Btn { text: cleanRun.showLog ? "Hide log" : "Show log"; icon: Theme.iList; onClicked: cleanRun.showLog = !cleanRun.showLog }
                Item { Layout.fillWidth: true }
                Btn { visible: !StorageState.cleaning; text: "Close"; kind: "primary"; onClicked: cleanRun.visible = false }
            }
        }
    }

    Modal {
        id: inspect
        property var item: ({})
        panelWidth: 700
        panelHeight: 380
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 8
            Label { text: inspect.item.name || ""; font.pixelSize: Theme.fsBig + 2; font.bold: true; Layout.fillWidth: true }
            KV { k: "Path"; v: inspect.item.path || ""; mono: true }
            KV { k: "Size"; v: Theme.bytes(inspect.item.bytes) + " · " + (inspect.item.files || 0).toLocaleString() + " file(s)" }
            KV { k: "Classification"; v: (inspect.item.classification || "") + " · " + (inspect.item.category || "") }
            KV { k: "Last modified"; v: Theme.date(inspect.item.modified) }
            KV { k: "Protection"; v: inspect.item.protected || "none"; vColor: inspect.item.protected ? Theme.warning : Theme.fg }
            KV { k: "Rebuildable"; v: inspect.item.rebuildable ? "yes — can be regenerated" : "no / unknown" }
            KV { k: "In Git repository"; v: inspect.item.inRepo ? "yes" : "no" }
            Label { visible: !!inspect.item.hint; text: inspect.item.hint || ""; color: Theme.tertiary; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            Item { Layout.fillHeight: true }
            RowLayout {
                Item { Layout.fillWidth: true }
                Btn { text: "Open Folder"; icon: Theme.iFolder; onClicked: StorageState.openFolder(inspect.item.path) }
                Btn { text: "Close"; kind: "primary"; onClicked: inspect.visible = false }
            }
        }
    }

    Modal {
        id: trashConfirm
        property var item: ({})
        panelWidth: 680
        panelHeight: 320
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10
            Label { text: "Move to Trash?"; font.pixelSize: Theme.fsBig + 2; font.bold: true }
            Label { text: "This exact item will be moved to the Trash (not deleted). You can restore it from the Trash until you empty it."; color: Theme.fgDim; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            Label { text: trashConfirm.item.path || ""; font.family: Theme.mono; color: Theme.warning; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true }
            KV { k: "Size"; v: Theme.bytes(trashConfirm.item.bytes) + " · " + (trashConfirm.item.files || 0).toLocaleString() + " file(s)" }
            KV { k: "Classification"; v: trashConfirm.item.classification || "" }
            Item { Layout.fillHeight: true }
            RowLayout {
                Item { Layout.fillWidth: true }
                Btn { text: "Cancel"; onClicked: trashConfirm.visible = false }
                Btn {
                    text: "Move to Trash"; kind: "danger"; icon: Theme.iTrash
                    onClicked: { StorageState.trash(trashConfirm.item.path); trashConfirm.visible = false; }
                }
            }
        }
    }

    // ============================================================ inline components
    component Stat: Surface {
        id: stat
        property string title: ""
        property string value: ""
        property string sub: ""
        property color accent: Theme.primary
        Layout.fillWidth: true
        implicitHeight: 86
        halftone: true
        Column {
            x: 14; y: 12; spacing: 4
            Label { text: stat.title; color: Theme.fgDim }
            Label { text: stat.value; font.pixelSize: Theme.fsHuge; font.bold: true; color: stat.accent }
            Label { text: stat.sub; color: Theme.fgDim; font.pixelSize: Theme.fsSmall }
        }
    }
    component Tab: Btn {
        property string key: ""
        kind: app.page === key ? "primary" : "normal"
        onClicked: app.page = key
    }
}
