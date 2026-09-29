import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.shared

// Full NixOS Updater UI. Checking is read-only; every mutation goes through a
// reviewed plan and an explicit confirmation.
Item {
    id: app
    readonly property var st: UpdaterState.status
    readonly property var sys: st.system || ({})
    readonly property var kern: st.kernel || ({})
    readonly property var np: st.nixpkgs || ({})
    readonly property var fp: st.flatpak || ({})
    readonly property var ax: st.ambxst || ({})
    readonly property var mods: st.mods || ({})
    readonly property var inputs: st.flakeInputs || []
    readonly property var repo: st.flakeRepo || ({})

    function fpUpdates(scope) { return ((fp[scope] || {}).updates || []); }
    function openPlan(only) { planModal.only = only || []; UpdaterState.loadPlan(); planModal.visible = true; }

    Rectangle { anchors.fill: parent; color: Theme.background }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        // ---------------------------------------------------------- header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Icon { icon: Theme.iCube; size: 26 }
            ColumnLayout {
                spacing: 2
                Label { text: "NixOS Updater"; font.pixelSize: Theme.fsHuge; font.bold: true }
                Label {
                    text: (sys.hostname || "") + " · NixOS " + (sys.nixosVersion || "?") + " · last checked " + Theme.ago(st.checkedAt)
                    color: Theme.fgDim
                }
            }
            Item { Layout.fillWidth: true }
            Chip {
                text: UpdaterState.state === "updates" ? UpdaterState.updateCount + " updates available"
                    : UpdaterState.state === "checking" ? "Checking…"
                    : (UpdaterState.summary.headline || "Not checked")
                tone: UpdaterState.state === "updates" ? "info" : UpdaterState.state === "error" ? "error"
                    : UpdaterState.state === "reboot" ? "warn" : UpdaterState.state === "up-to-date" ? "ok" : "muted"
            }
            Btn {
                icon: Theme.iSync; text: "Check for Updates"
                busy: UpdaterState.checking
                enabled: !UpdaterState.running
                onClicked: UpdaterState.check()
            }
            Btn {
                icon: Theme.iDown; text: "Update All…"; kind: "primary"
                enabled: !UpdaterState.running && !UpdaterState.checking && st.checkedAt > 0
                onClicked: app.openPlan([])
            }
        }
        Label {
            visible: UpdaterState.checkError !== "" || (st.errors || []).length > 0
            text: UpdaterState.checkError !== "" ? UpdaterState.checkError : (st.errors || []).join(" · ")
            color: Theme.error
            Layout.fillWidth: true
        }
        Label {
            visible: !!sys.rebootRecommended || !!kern.rebootRequired
            text: "⚠ Reboot recommended: " + (sys.rebootReason || ("running kernel " + kern.running + ", configured " + kern.configured))
            color: Theme.warning
            Layout.fillWidth: true
        }

        // ---------------------------------------------------------- cards
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            GridLayout {
                width: parent.width
                columns: width > 1000 ? 2 : 1
                columnSpacing: 14
                rowSpacing: 14

                Card {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    icon: Theme.iCube; title: "NixOS"
                    chip: sys.rebootRecommended ? "reboot recommended" : "active"
                    chipTone: sys.rebootRecommended ? "warn" : "ok"
                    KV { k: "Current generation"; v: (sys.generation ?? "?") + "  (" + Theme.date(sys.generationDate) + ")" }
                    KV { k: "Generations"; v: (sys.generationCount ?? "?") + " on disk" }
                    KV { k: "Running system"; v: sys.currentIsBooted ? "same as booted" : "differs from booted system"; vColor: sys.currentIsBooted ? Theme.fg : Theme.warning }
                    KV { k: "Flake"; v: (repo.path || "/etc/nixos") + (repo.git ? " (Git)" : " (not a Git repo)"); mono: true }
                    Label { text: repo.note || ""; color: Theme.fgDim; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: Theme.fsSmall }
                    RowLayout {
                        Btn {
                            icon: Theme.iSync; text: "Rebuild NixOS…"
                            enabled: !UpdaterState.running
                            onClicked: app.openPlan(["rebuild"])
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    icon: Theme.iDown; title: "nixpkgs"
                    chip: np.error ? "check failed" : !np.latest ? "not checked" : np.updateAvailable ? "update available" : "up to date"
                    chipTone: np.error ? "error" : np.updateAvailable ? "info" : np.latest ? "ok" : "muted"
                    KV { k: "Channel"; v: np.channel || "—" }
                    KV { k: "Locked release"; v: np.current || "—"; mono: true }
                    KV { k: "Latest release"; v: np.latest || "—"; mono: true; vColor: np.updateAvailable ? Theme.tertiary : Theme.fg }
                    Label { visible: !!np.error; text: np.error || ""; color: Theme.error; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Label {
                        text: "nixpkgs is pinned to a channel release URL in flake.nix, so updating rewrites that URL and re-locks it. The original files are backed up first."
                        color: Theme.fgDim; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: Theme.fsSmall
                    }
                    RowLayout {
                        Btn {
                            icon: Theme.iDown; text: "Update nixpkgs…"
                            enabled: !UpdaterState.running && !!np.updateAvailable
                            onClicked: app.openPlan(["nixpkgs", "rebuild"])
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    id: inputsCard
                    icon: Theme.iList; title: "Flake Inputs"
                    readonly property int outdated: app.inputs.filter(i => i.outdated).length
                    chip: outdated > 0 ? outdated + " outdated" : "none outdated"
                    chipTone: outdated > 0 ? "info" : "ok"
                    Repeater {
                        model: app.inputs
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 10
                            Label { text: modelData.name; font.bold: true; Layout.preferredWidth: 110 }
                            Chip { text: modelData.pin + "-pinned"; tone: modelData.updatableByLock ? "info" : "muted" }
                            Label {
                                Layout.fillWidth: true
                                font.family: Theme.mono
                                color: modelData.error ? Theme.error : modelData.newerUpstream ? Theme.tertiary : Theme.fgDim
                                text: modelData.error ? modelData.error
                                    : modelData.name === "nixpkgs" ? "see nixpkgs card"
                                    : (modelData.ref ? modelData.ref + " " : "") + (modelData.shortRev || "")
                                      + (modelData.latest ? (modelData.newerUpstream ? "  → newer upstream " + (modelData.latest.tag || modelData.latest.shortRev) : "  (latest)") : "")
                            }
                        }
                    }
                    Label {
                        text: "Pinned inputs (commit, tag, release) do not move with “nix flake update”; newer upstream versions are shown but only changed by editing flake.nix yourself."
                        color: Theme.fgDim; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: Theme.fsSmall
                    }
                    RowLayout {
                        Btn {
                            icon: Theme.iDown; text: "Update Flake Inputs…"
                            enabled: !UpdaterState.running && inputsCard.outdated > 0
                            onClicked: app.openPlan(["flake-inputs", "rebuild"])
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    visible: !kern.hidden
                    icon: Theme.iCpu; title: "Linux Kernel"
                    chip: kern.rebootRequired ? "reboot required" : kern.updateChangesKernel ? "new kernel available" : "current"
                    chipTone: kern.rebootRequired ? "warn" : kern.updateChangesKernel ? "info" : "ok"
                    KV { k: "Running kernel"; v: kern.running || "—"; mono: true }
                    KV { k: "Configured kernel"; v: (kern.configured || "—") + (kern.attr ? "  (" + kern.attr + ")" : ""); mono: true; vColor: kern.configured && kern.configured !== kern.running ? Theme.warning : Theme.fg }
                    KV { k: "Next boot"; v: kern.nextBoot || "—"; mono: true }
                    KV { k: "After nixpkgs update"; v: kern.availableAfterUpdate || "—"; mono: true; vColor: kern.updateChangesKernel ? Theme.tertiary : Theme.fg }
                    Label {
                        text: "A new kernel only becomes active after rebooting into it. The running kernel is what uname reports right now."
                        color: Theme.fgDim; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: Theme.fsSmall
                    }
                }

                Card {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    visible: !fp.hidden
                    icon: Theme.iCube; title: "Flatpak"
                    readonly property int n: app.fpUpdates("user").length + app.fpUpdates("system").length
                    chip: !fp.available ? "not available" : n > 0 ? n + (n === 1 ? " update" : " updates") : "up to date"
                    chipTone: n > 0 ? "info" : fp.available ? "ok" : "muted"
                    KV { k: "User"; v: ((fp.user || {}).installed ?? 0) + " installed · " + app.fpUpdates("user").length + " updates" }
                    KV { k: "System"; v: ((fp.system || {}).installed ?? 0) + " installed · " + app.fpUpdates("system").length + " updates" }
                    Repeater {
                        model: app.fpUpdates("user").concat(app.fpUpdates("system"))
                        Label {
                            required property var modelData
                            text: "• " + modelData.ref + (modelData.downloadSize ? "  (" + modelData.downloadSize + ")" : "")
                            color: Theme.tertiary; font.family: Theme.mono; Layout.fillWidth: true
                        }
                    }
                    Label { visible: !!((fp.user || {}).error || (fp.system || {}).error); text: (fp.user || {}).error || (fp.system || {}).error || ""; color: Theme.error; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    RowLayout {
                        spacing: 8
                        Btn {
                            icon: Theme.iDown; text: "Update user Flatpaks"
                            enabled: !UpdaterState.running && app.fpUpdates("user").length > 0
                            onClicked: app.openPlan(["flatpak-user"])
                        }
                        Btn {
                            icon: Theme.iDown; text: "Update system Flatpaks"
                            enabled: !UpdaterState.running && app.fpUpdates("system").length > 0
                            onClicked: app.openPlan(["flatpak-system"])
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    visible: !ax.hidden
                    icon: Theme.iGear; title: "Ambxst"
                    chip: !ax.available ? "not installed" : ax.updateAvailable ? ax.latestTag + " available" : ax.latestTag ? "up to date" : "not checked"
                    chipTone: ax.updateAvailable ? "info" : ax.latestTag ? "ok" : "muted"
                    KV { k: "Installed version"; v: ax.version || "—" }
                    KV { k: "Latest release"; v: ax.latestTag || "—"; vColor: ax.updateAvailable ? Theme.tertiary : Theme.fg }
                    KV { k: "Pinned revision"; v: (ax.pinnedRev || "—").substring(0, 12); mono: true }
                    KV { k: "Upstream HEAD"; v: (ax.upstreamRev || "—").substring(0, 12); mono: true }
                    KV { k: "Pin file"; v: ax.pinFile || "—"; mono: true }
                    Label {
                        text: ax.note || ""
                        color: Theme.fgDim; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: Theme.fsSmall
                    }
                }

                Card {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    visible: !mods.hidden
                    icon: Theme.iGear; title: "Ambxst Mods"
                    chip: !mods.available ? "unavailable" : (mods.mods || []).length === 0 ? "none installed" : (mods.updateCount > 0 ? mods.updateCount + " updates" : "up to date")
                    chipTone: mods.updateCount > 0 ? "info" : "muted"
                    KV { k: "Active generation"; v: mods.activeGeneration || "—"; mono: true }
                    Repeater {
                        model: mods.mods || []
                        KV {
                            required property var modelData
                            k: modelData.id
                            v: (modelData.enabled ? "enabled" : "disabled") + " · " + modelData.version
                               + (modelData.updateAvailable === true ? " → " + modelData.sourceVersion : modelData.updateAvailable === null ? " (update status unknown)" : "")
                        }
                    }
                    Label {
                        text: "Managed with the ambxst mods CLI. Updates run “ambxst mods update <id>” and never edit Ambxst’s state files directly."
                        color: Theme.fgDim; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: Theme.fsSmall
                    }
                    RowLayout {
                        Btn {
                            icon: Theme.iDown; text: "Update Ambxst Mods…"
                            enabled: !UpdaterState.running && (mods.updateCount || 0) > 0
                            onClicked: app.openPlan(["mods"])
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    id: lastRunCard
                    icon: Theme.iList; title: "Last Run"
                    readonly property var lr: st.lastRun || ({})
                    readonly property var pr: st.pendingRevert || null
                    chip: !lr.action ? "none" : lr.ok ? "succeeded" : "failed"
                    chipTone: !lr.action ? "muted" : lr.ok ? "ok" : "error"
                    KV { k: "Action"; v: (lastRunCard.lr.action || "—") + (lastRunCard.lr.at ? "  (" + Theme.date(lastRunCard.lr.at) + ")" : "") }
                    Label { visible: !!lastRunCard.lr.message; text: lastRunCard.lr.message || ""; color: lastRunCard.lr.ok ? Theme.fg : Theme.error; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    KV { k: "Log"; v: lastRunCard.lr.log || "—"; mono: true }
                    Label {
                        visible: !!lastRunCard.pr
                        text: lastRunCard.pr ? "flake.nix / flake.lock were changed by this tool (backup " + lastRunCard.pr.backupId + ")." : ""
                        color: Theme.warning; Layout.fillWidth: true; wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        spacing: 8
                        Btn { text: "Open log"; icon: Theme.iFile; enabled: !!lastRunCard.lr.log; onClicked: Quickshell.execDetached(["xdg-open", lastRunCard.lr.log]) }
                        Btn {
                            visible: !!lastRunCard.pr
                            text: "Revert flake changes…"; icon: Theme.iUndo; kind: "danger"
                            enabled: !UpdaterState.running
                            onClicked: revertModal.visible = true
                        }
                    }
                }
            }
        }
    }

    // ============================================================ plan / review
    Modal {
        id: planModal
        property var only: []
        property var selected: ({})
        panelWidth: 760
        panelHeight: 620
        readonly property var steps: {
            const p = UpdaterState.plan;
            if (!p) return [];
            return only.length === 0 ? p.steps : p.steps.filter(s => only.indexOf(s.id) >= 0);
        }
        onStepsChanged: {
            const sel = {};
            for (const s of steps) sel[s.id] = only.length > 0 ? true : !!s["default"];
            selected = sel;
        }
        readonly property var chosen: steps.filter(s => selected[s.id])

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            Label { text: planModal.only.length === 0 ? "Review update plan" : "Review planned operation"; font.pixelSize: Theme.fsBig + 2; font.bold: true }
            Label { text: "Nothing has changed yet. Select the steps to run; they execute in this order and stop at the first failure."; color: Theme.fgDim; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            Spinner { visible: !UpdaterState.plan; size: 20 }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                ColumnLayout {
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: planModal.steps
                        Surface {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: stepCol.implicitHeight + 20
                            halftone: false
                            ColumnLayout {
                                id: stepCol
                                x: 12; y: 10
                                width: parent.width - 24
                                spacing: 4
                                RowLayout {
                                    Check {
                                        checked: !!planModal.selected[modelData.id]
                                        onToggled: v => { const s = Object.assign({}, planModal.selected); s[modelData.id] = v; planModal.selected = s; }
                                    }
                                    Label { text: modelData.title; font.bold: true; Layout.fillWidth: true }
                                    Chip { visible: !!modelData.privileged; text: "needs authentication"; tone: "warn" }
                                }
                                Repeater {
                                    model: modelData.detail || []
                                    Label { required property string modelData; text: "  " + modelData; color: Theme.fgDim; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                }
                                Repeater {
                                    model: modelData.commands || []
                                    Label { required property string modelData; text: "  $ " + modelData; color: Theme.tertiary; font.family: Theme.mono; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
                                }
                            }
                        }
                    }
                    Repeater {
                        model: UpdaterState.plan ? UpdaterState.plan.warnings : []
                        Label { required property string modelData; text: "⚠ " + modelData; color: Theme.warning; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: planModal.chosen.length + " step(s) selected"; color: Theme.fgDim; Layout.fillWidth: true }
                Btn { text: "Cancel"; onClicked: planModal.visible = false }
                Btn {
                    text: "Start " + planModal.chosen.length + " step(s)"; icon: Theme.iCheck; kind: "primary"
                    enabled: planModal.chosen.length > 0
                    onClicked: {
                        const ids = planModal.chosen.map(s => s.id);
                        const args = ["update-all", "--steps", ids.join(",")];
                        const np = planModal.chosen.find(s => s.id === "nixpkgs");
                        if (np) args.push("--release", np.release);
                        const fi = planModal.chosen.find(s => s.id === "flake-inputs");
                        if (fi) args.push("--inputs", fi.inputs.join(","));
                        planModal.visible = false;
                        runModal.titles = planModal.chosen.reduce((m, s) => { m[s.id] = s.title; return m; }, {});
                        runModal.order = ids;
                        UpdaterState.apply(args);
                    }
                }
            }
        }
    }

    // ============================================================ run / results
    Connections {
        target: UpdaterState
        function onRunStarted() { log.clear(); runModal.visible = true; }
        function onLogLine(line) { log.append(line); }
    }
    Modal {
        id: runModal
        property var titles: ({})
        property var order: []
        property bool showLog: false
        panelWidth: 900
        panelHeight: showLog ? 700 : 420
        readonly property var res: UpdaterState.result

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            RowLayout {
                Spinner { visible: UpdaterState.running; size: 22 }
                Icon { visible: !UpdaterState.running && !!runModal.res; icon: runModal.res && runModal.res.ok ? Theme.iCheck : Theme.iAlert; color: runModal.res && runModal.res.ok ? Theme.ok : Theme.error; size: 22 }
                Label {
                    text: UpdaterState.running ? (UpdaterState.phase || "Working…") : (runModal.res ? runModal.res.message : "")
                    font.pixelSize: Theme.fsBig + 2; font.bold: true
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone
                }
            }
            Indeterminate {
                visible: UpdaterState.running
                Layout.fillWidth: true
                barColor: UpdaterState.authState === "waiting" ? Theme.warning : Theme.primary
            }
            AuthBanner {
                Layout.fillWidth: true
                state: UpdaterState.authState
                message: UpdaterState.authMessage
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Label {
                    visible: runModal.order.length > 0
                    text: {
                        const ord = runModal.order;
                        let done = 0, cur = "";
                        for (let i = 0; i < ord.length; i++) {
                            const st = (UpdaterState.steps[ord[i]] || {}).status || "pending";
                            if (st === "ok" || st === "failed" || st === "cancelled" || st === "skipped") done++;
                            else if (st === "running") cur = runModal.titles[ord[i]] || ord[i];
                        }
                        const n = Math.min(done + (UpdaterState.running && cur ? 1 : 0), ord.length);
                        return "Step " + n + " of " + ord.length + (cur ? " · " + cur : "");
                    }
                    color: Theme.fgDim
                    font.family: Theme.mono
                    font.pixelSize: Theme.fsSmall
                    Layout.fillWidth: true
                }
                Label {
                    visible: UpdaterState.durationText !== ""
                    text: UpdaterState.durationText
                    color: Theme.tertiary
                    font.family: Theme.mono
                    font.pixelSize: Theme.fsSmall
                }
            }
            Repeater {
                model: runModal.order
                RowLayout {
                    required property string modelData
                    readonly property string status: (UpdaterState.steps[modelData] || {}).status || "pending"
                    spacing: 10
                    Spinner { visible: status === "running"; size: 14 }
                    Icon {
                        visible: status !== "running"; size: 14
                        icon: status === "ok" ? Theme.iCheck : status === "failed" || status === "cancelled" ? Theme.iX : Theme.iCaretRight
                        color: status === "ok" ? Theme.ok : status === "failed" ? Theme.error : Theme.fgDim
                    }
                    Label { text: runModal.titles[modelData] || modelData; Layout.fillWidth: true }
                    Label { text: status; color: Theme.fgDim }
                }
            }
            Label {
                visible: !!(runModal.res && runModal.res.rebootRequired)
                text: "Reboot required to use the new kernel " + (runModal.res ? runModal.res.newKernel || "" : "") + ". The system will not reboot automatically."
                color: Theme.warning; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            Label {
                visible: !!(runModal.res && (runModal.res.generationBefore !== undefined || runModal.res.generationAfter !== undefined))
                text: "Generation " + (runModal.res.generationBefore ?? "?") + " → " + (runModal.res.generationAfter ?? "?")
                    + (runModal.res.duration ? "  ·  " + runModal.res.duration : "")
                color: Theme.primary; font.family: Theme.mono; Layout.fillWidth: true
            }
            Repeater {
                model: runModal.res && runModal.res.diff ? runModal.res.diff : []
                Label {
                    required property var modelData
                    text: "flake.lock  " + modelData.input + ": " + String(modelData.from).slice(-40) + " → " + String(modelData.to).slice(-40)
                    font.family: Theme.mono; color: Theme.tertiary; Layout.fillWidth: true; elide: Text.ElideMiddle
                }
            }
            Label {
                visible: !!(runModal.res && !runModal.res.ok && runModal.res.revertAvailable)
                text: "The flake files were changed before the failure. The running system was not changed; you can revert flake.nix/flake.lock to their previous state."
                color: Theme.warning; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            Label {
                visible: UpdaterState.running && !UpdaterState.cancellable
                text: "This phase cannot be cancelled safely (activating the new system)."
                color: Theme.fgDim; Layout.fillWidth: true
            }
            LogView { id: log; visible: runModal.showLog; Layout.fillWidth: true; Layout.fillHeight: true }
            Item { visible: !runModal.showLog; Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Btn { text: runModal.showLog ? "Hide log" : "Show log"; icon: Theme.iList; onClicked: runModal.showLog = !runModal.showLog }
                Label { text: UpdaterState.logPath; color: Theme.fgDim; font.family: Theme.mono; font.pixelSize: Theme.fsSmall; Layout.fillWidth: true; elide: Text.ElideLeft }
                Btn {
                    visible: UpdaterState.running
                    text: UpdaterState.cancelRequested ? "Cancelling…" : "Cancel"; icon: Theme.iX; kind: "danger"
                    enabled: UpdaterState.cancellable && !UpdaterState.cancelRequested
                    onClicked: UpdaterState.cancel()
                }
                Btn {
                    visible: !UpdaterState.running && !!(runModal.res && runModal.res.revertAvailable && !runModal.res.ok)
                    text: "Revert flake changes…"; icon: Theme.iUndo; kind: "danger"
                    onClicked: { runModal.visible = false; revertModal.visible = true; }
                }
                Btn {
                    visible: !UpdaterState.running
                    text: "Close"; kind: "primary"
                    onClicked: { runModal.visible = false; UpdaterState.refreshLocal(); }
                }
            }
        }
    }

    // ============================================================ revert
    Modal {
        id: revertModal
        panelWidth: 620
        panelHeight: 300
        readonly property var pr: app.st.pendingRevert || null
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            Label { text: "Revert flake changes?"; font.pixelSize: Theme.fsBig + 2; font.bold: true }
            Label {
                text: "Restores flake.lock (and the nixpkgs URL in flake.nix) from backup " + (revertModal.pr ? revertModal.pr.backupId : "?")
                      + ". A file is only restored if it still matches what this tool wrote, so later edits are never overwritten. Nothing is rebuilt automatically."
                wrapMode: Text.WordWrap; Layout.fillWidth: true; color: Theme.fgDim
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Btn { text: "Cancel"; onClicked: revertModal.visible = false }
                Btn {
                    text: "Revert"; kind: "danger"; icon: Theme.iUndo
                    enabled: !!revertModal.pr
                    onClicked: {
                        revertModal.visible = false;
                        runModal.titles = ({}); runModal.order = [];
                        UpdaterState.apply(["revert-lock", "--backup", revertModal.pr.backupId]);
                    }
                }
            }
        }
    }
}
