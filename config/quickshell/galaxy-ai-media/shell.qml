import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Galaxy AI Media: a front end to the `ai-media` hub (catalog, runners, jobs, local LLM chat).
// Everything it shows and does goes through the same CLI that scripts and the MCP server use, so
// jobs started here are visible there and the other way round. No inference runs in this process.
ShellRoot {
    id: root
    property bool opened: false
    property string page: "models"            // models | run | compare | chat | jobs
    property var models: []
    property var jobs: []
    property var hw: ({})
    property var llm: ({ servers: {}, models: [], gguf_on_disk: [] })
    property var refreshInfo: ({})
    property var catalogInfo: ({})
    property string capability: ""            // "" = all
    property bool onlyInstalled: false
    property bool onlyFits: false
    property bool onlyBenchmarked: false
    property string selectedId: ""
    property var compareIds: []
    property var form: ({})
    property string notice: ""
    property bool noticeIsError: false
    property bool loading: false
    property bool refreshing: false
    property bool hostedConfirmed: false
    // chat
    property string chatModel: ""
    property var chatMessages: []            // {role, content}
    property string chatPartial: ""
    property var chatStats: null
    property real temperature: 0.7
    property int maxTokens: 512
    property int contextLen: 8192
    property int gpuLayers: -1
    readonly property var caps: [["", "All"], ["text-to-image", "Text→Image"], ["image-to-image", "Image→Image"], ["3d", "3D"],
                                 ["video-edit", "Video"], ["music", "Music"], ["llm", "LLM"]]
    readonly property var pages: [["models", "Details"], ["run", "Run"], ["compare", "Compare"], ["chat", "Chat"], ["jobs", "Jobs"]]
    readonly property var visibleModels: models.filter(m => (!capability || m.capability === capability) && (!onlyInstalled || m.installed)
        && (!onlyFits || m.fit.status === "gpu" || m.fit.status === "gpu-offload") && (!onlyBenchmarked || m.local_benchmarks + m.published_benchmarks > 0))
    readonly property var selected: models.find(m => m.id === selectedId) || visibleModels[0] || null
    readonly property var activeJobs: jobs.filter(j => ["queued", "waiting-gpu", "running", "cancelling"].indexOf(j.status) >= 0)
    readonly property string cli: Quickshell.env("AI_MEDIA_BIN") || "ai-media"

    function say(text, isError) { notice = text; noticeIsError = !!isError }
    function fitColor(f) { return f.status === "gpu" ? Galaxy.ok : f.status === "gpu-offload" ? Galaxy.warn : f.status === "cpu" ? Galaxy.lavender
        : f.status === "no-fit" ? Galaxy.err : Galaxy.label }
    function fitLabel(f) { const n = { "gpu": "fits GPU", "gpu-offload": "GPU + offload", "cpu": "CPU only", "no-fit": "does not fit", "unknown": "fit unknown", "n/a": "no weights" }
        return (n[f.status] || f.status) + (f.basis === "measured" ? " · measured" : f.basis === "estimated" ? " · estimated" : "") }
    function stateLabel(m) { return m.runnable ? "ready" : m.installed ? "installed" : (m.availability || "weights") !== "weights" ? "research" : m.adapter ? "not installed" : "unsupported" }
    // Percent-encoded UTF-8 JSON: plain ASCII in argv, and no dependence on how the engine's btoa treats strings.
    function enc(obj) { return encodeURIComponent(JSON.stringify(obj)) }
    function open() { opened = true; loadAll() }
    function close() { opened = false }
    function loadAll() { loading = true; catalogProc.running = true; stateProc.running = true }
    function select(id) { selectedId = id; form = ({}); hostedConfirmed = false; say("", false) }
    function setField(k, v) { const f = Object.assign({}, form); if (v === "" || v === undefined) delete f[k]; else f[k] = v; form = f }
    function toggleCompare(id) { const c = compareIds.slice(); const i = c.indexOf(id); if (i >= 0) c.splice(i, 1); else if (c.length < 3) c.push(id); else { say("Compare holds three models; remove one first", true); return } compareIds = c }
    function refreshCatalog() { if (refreshing) return; refreshing = true; say("Refreshing catalog metadata (no weights or code are downloaded)…", false); refreshProc.running = true }
    function runSelected() {
        const m = selected
        if (!m || runProc.running) return
        if (!m.runnable) { say("Cannot run: " + m.missing.map(x => x.what).join("; "), true); return }
        if (m.hosted_service && !hostedConfirmed) { say(m.hosted_service + " is a hosted service: your prompt and files would leave this machine. Tick the confirmation first.", true); return }
        const params = {}
        for (const p of m.params) { const v = form[p.name]; if (v === undefined || v === "") continue
            params[p.name] = p.type === "int" ? parseInt(v) : p.type === "float" ? parseFloat(v) : v }
        runProc.command = ["python3", Quickshell.shellPath("bridge.py"), "run", enc({ model: m.id, params: params, allow_hosted: hostedConfirmed })]
        runProc.running = true
    }
    function jobAction(verb, id) { if (jobProc.running) return; jobProc.command = [cli, "jobs", verb, id, "--json"]; jobProc.running = true }
    function sendChat(text) {
        text = text.trim()
        if (!text.length || chatProc.running) return
        if (!chatModel.length) { say("No local LLM is being served. Start one: ollama serve, or llama-server -m MODEL.gguf -ngl 99 --jinja", true); return }
        const msgs = chatMessages.concat([{ role: "user", content: text }])
        chatMessages = msgs; chatPartial = ""; chatStats = null
        chatProc.command = ["python3", Quickshell.shellPath("bridge.py"), "chat", enc({ model: chatModel, messages: msgs,
            options: { temperature: temperature, max_tokens: maxTokens, context: contextLen, gpu_layers: gpuLayers } })]
        chatProc.running = true
    }
    function stopChat() { if (chatProc.running) { chatProc.running = false; if (chatPartial.length) chatMessages = chatMessages.concat([{ role: "assistant", content: chatPartial + " ▪ stopped" }]); chatPartial = "" } }
    function clearChat() { stopChat(); chatMessages = []; chatStats = null }

    Process { id: catalogProc; command: [root.cli, "catalog", "list", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text); if (Array.isArray(d)) root.models = d; else if (d.error) root.say(d.error.message, true) }
            catch (e) { root.say("`ai-media` did not answer. Is ai-media-cli installed and on PATH? (scripts/install_qwen_wrappers.sh)", true) } root.loading = false } } }
    Process { id: stateProc; command: [root.cli, "state", "--json"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text); root.hw = d.hardware; root.jobs = d.jobs; root.llm = d.llm; root.refreshInfo = d.refresh; root.catalogInfo = d.catalog
            const served = d.llm.models.map(m => m.ref); if (served.indexOf(root.chatModel) < 0) root.chatModel = served[0] || "" } catch (e) {} } } }
    // Job state lives on disk; polling it is all it takes to recover after the popup was closed or the shell restarted.
    Timer { interval: root.activeJobs.length ? 1000 : 5000; repeat: true; running: root.opened; onTriggered: if (!stateProc.running) stateProc.running = true }
    Process { id: refreshProc; command: [root.cli, "catalog", "refresh", "--json"]
        stdout: StdioCollector { onStreamFinished: { root.refreshing = false; try { const r = JSON.parse(text)
            root.say(r.updated ? "Catalog refreshed: " + r.updated + " updated" + (r.failed ? ", " + r.failed + " unreachable (kept as they were)" : "")
                : "Refresh could not reach any source; the existing catalog is unchanged", !r.updated) } catch (e) { root.say("Refresh failed; the existing catalog is unchanged", true) }
            root.loadAll() } } }
    Process { id: runProc
        stdout: StdioCollector { onStreamFinished: { try { const r = JSON.parse(text)
            if (r.error) root.say(r.error.message + (r.error.hint ? " — " + r.error.hint : ""), true)
            else { root.say("Job " + r.job_id + " " + r.status, false); root.page = "jobs" } } catch (e) { root.say("The runner did not answer", true) }
            stateProc.running = true } } }
    Process { id: jobProc; stdout: StdioCollector { onStreamFinished: { try { const r = JSON.parse(text); if (r.error) root.say(r.error.message, true) } catch (e) {} stateProc.running = true } } }
    Process { id: chatProc
        stdout: SplitParser { onRead: line => { let ev; try { ev = JSON.parse(line) } catch (e) { return }
            if (ev.type === "token") root.chatPartial += ev.text
            else if (ev.type === "done") { root.chatMessages = root.chatMessages.concat([{ role: "assistant", content: ev.text }]); root.chatPartial = ""; root.chatStats = ev.stats }
            else if (ev.type === "error" || ev.error) { const er = ev.error || ev; root.say(er.message + (er.hint ? " — " + er.hint : ""), true) } } } }

    IpcHandler {
        target: "aimedia"
        function open(): void { root.open() }
        function close(): void { root.close() }
        function toggle(): void { if (root.opened) root.close(); else root.open() }
        function show(page: string): void { if (root.pages.some(p => p[0] === page)) root.page = page; root.open() }
        // test hooks
        function pick(id: string): void { root.select(id) }
        function filter(capability: string): void { root.capability = capability }
        function field(name: string, value: string): void { root.setField(name, value) }
        function run(): void { root.runSelected() }
        function cancel(id: string): void { root.jobAction("cancel", id) }
        function compare(id: string): void { root.toggleCompare(id) }
        function ask(text: string): void { root.sendChat(text) }
        function reload(): void { root.loadAll() }
        function refresh(): void { root.refreshCatalog() }
    }

    component Pill: Rectangle {
        property string text: ""; property color tint: Galaxy.label
        implicitWidth: pt.implicitWidth + 14; implicitHeight: 20; radius: 10; color: "transparent"; border.color: tint
        Text { id: pt; anchors.centerIn: parent; text: parent.text; font.family: Galaxy.font; font.pixelSize: 10; color: parent.tint }
    }
    component Chip: Rectangle {
        property string text: ""; property bool on: false; signal clicked()
        implicitWidth: ct.implicitWidth + 18; implicitHeight: 26; radius: 13; color: on ? Galaxy.raised : "transparent"; border.color: on ? Galaxy.purple : Galaxy.line
        Text { id: ct; anchors.centerIn: parent; text: parent.text; font.family: Galaxy.font; font.pixelSize: 11; color: parent.on ? Galaxy.ink : Galaxy.label }
        MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
    }
    component KV: RowLayout {
        property string k: ""; property string v: ""; property color tint: Galaxy.ink
        Layout.fillWidth: true; spacing: 10
        Text { text: parent.k; Layout.preferredWidth: 110; font.family: Galaxy.font; font.pixelSize: 11; color: Galaxy.label }
        Text { text: parent.v; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; font.family: Galaxy.font; font.pixelSize: 12; color: parent.tint }
    }
    component Head: Text { font.family: Galaxy.font; font.pixelSize: 11; color: Galaxy.lavender; topPadding: 6 }
    component Input: TextField {
        Layout.fillWidth: true; color: Galaxy.ink; placeholderTextColor: Galaxy.dim; selectionColor: Galaxy.violet
        font.family: Galaxy.font; font.pixelSize: 13; padding: 9
        background: Rectangle { radius: Galaxy.radiusControl; color: Galaxy.base; border.color: parent.activeFocus ? Galaxy.purple : Galaxy.line }
    }

    PanelWindow {
        visible: root.opened
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "galaxy-ai-media"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle { anchors.fill: parent; color: "#8007060d"; MouseArea { anchors.fill: parent; onClicked: root.close() } }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(1240, parent.width - 80); height: Math.min(760, parent.height - 80); radius: Galaxy.radiusWindow; color: "transparent"
            Nebula { anchors.fill: parent; radius: card.radius; seed: 73; glow: 1.0; hot: root.activeJobs.length > 0 }
            MouseArea { anchors.fill: parent }
            focus: true
            Keys.onEscapePressed: root.close()
            Connections { target: root; function onOpenedChanged() { if (root.opened) card.forceActiveFocus() } }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 18; spacing: 10

                // ---------------------------------------------------------------- header
                RowLayout { Layout.fillWidth: true; spacing: 10
                    Text { text: "✦  A I   M E D I A"; font.family: Galaxy.font; font.pixelSize: 13; color: Galaxy.lavender }
                    Pill { text: root.hw.gpus && root.hw.gpus.length ? root.hw.gpus[0].name + " · " + root.hw.vram_free_gb + " / " + root.hw.vram_total_gb + " GB free" : "no GPU detected"
                        tint: root.hw.gpus && root.hw.gpus.length ? Galaxy.ok : Galaxy.err }
                    Pill { visible: root.hw.ram_gb !== undefined; text: "RAM " + root.hw.ram_gb + " GB · disk " + root.hw.disk_free_gb + " GB free" }
                    Pill { visible: root.activeJobs.length > 0; text: root.activeJobs.length + " job" + (root.activeJobs.length > 1 ? "s" : "") + " active"; tint: Galaxy.warn }
                    Item { Layout.fillWidth: true }
                    Text { font.family: Galaxy.font; font.pixelSize: 10; color: Galaxy.dim
                        text: "catalog: " + (root.catalogInfo.models || 0) + " models · last refresh " + (root.refreshInfo.last_success ? String(root.refreshInfo.last_success).slice(0, 16).replace("T", " ") : "never") }
                    GalaxyButton { text: root.refreshing ? "Refreshing…" : "Refresh"; enabled: !root.refreshing; hint: "Fetch upstream metadata only. Never downloads weights or code."; onClicked: root.refreshCatalog() }
                    GalaxyButton { text: "✕"; onClicked: root.close() }
                }

                RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 14

                    // ---------------------------------------------------------------- browser
                    ColumnLayout { Layout.preferredWidth: 400; Layout.maximumWidth: 400; Layout.fillHeight: true; spacing: 8
                        Flow { Layout.fillWidth: true; spacing: 6
                            Repeater { model: root.caps
                                Chip { required property var modelData; text: modelData[1]; on: root.capability === modelData[0]; onClicked: root.capability = modelData[0] } } }
                        Flow { Layout.fillWidth: true; spacing: 6
                            Chip { text: "Installed"; on: root.onlyInstalled; onClicked: root.onlyInstalled = !root.onlyInstalled }
                            Chip { text: "Fits this GPU"; on: root.onlyFits; onClicked: root.onlyFits = !root.onlyFits }
                            Chip { text: "Has benchmarks"; on: root.onlyBenchmarked; onClicked: root.onlyBenchmarked = !root.onlyBenchmarked } }
                        ListView {
                            id: modelList
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 4; boundsBehavior: Flickable.StopAtBounds
                            model: root.visibleModels
                            delegate: Rectangle {
                                id: mrow
                                required property var modelData
                                readonly property bool on: root.selected && root.selected.id === modelData.id
                                width: modelList.width; height: 54; radius: Galaxy.radiusControl
                                color: on ? Galaxy.raised : "transparent"; border.width: on ? 1 : 0; border.color: Galaxy.purple
                                ColumnLayout { anchors.fill: parent; anchors.margins: 8; spacing: 3
                                    RowLayout { Layout.fillWidth: true; spacing: 6
                                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: mrow.modelData.name; font.family: Galaxy.font; font.pixelSize: 13; color: Galaxy.ink }
                                        Text { visible: root.compareIds.indexOf(mrow.modelData.id) >= 0; text: "⇄"; font.pixelSize: 12; color: Galaxy.magenta } }
                                    RowLayout { spacing: 6
                                        Pill { text: root.stateLabel(mrow.modelData); tint: mrow.modelData.runnable ? Galaxy.ok : mrow.modelData.installed ? Galaxy.lavender : Galaxy.label }
                                        Pill { text: root.fitLabel(mrow.modelData.fit); tint: root.fitColor(mrow.modelData.fit) }
                                        Pill { visible: mrow.modelData.local_benchmarks + mrow.modelData.published_benchmarks > 0
                                            text: mrow.modelData.local_benchmarks + " local · " + mrow.modelData.published_benchmarks + " published" }
                                        Pill { visible: !mrow.modelData.local; text: "hosted"; tint: Galaxy.err } } }
                                MouseArea { anchors.fill: parent; onClicked: root.select(mrow.modelData.id) }
                            }
                            Text { anchors.centerIn: parent; visible: !root.visibleModels.length; font.family: Galaxy.font; font.pixelSize: 12; color: Galaxy.dim
                                text: root.loading ? "Loading catalog…" : root.models.length ? "No model matches these filters" : "Catalog unavailable" }
                        }
                    }

                    // ---------------------------------------------------------------- pages
                    ColumnLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 8
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Repeater { model: root.pages
                                Chip { required property var modelData; text: modelData[1] + (modelData[0] === "jobs" && root.jobs.length ? " (" + root.jobs.length + ")" : modelData[0] === "compare" && root.compareIds.length ? " (" + root.compareIds.length + ")" : "")
                                    on: root.page === modelData[0]; onClicked: root.page = modelData[0] } }
                            Item { Layout.fillWidth: true }
                            GalaxyButton { visible: !!root.selected && (root.page === "models" || root.page === "run")
                                text: root.selected && root.compareIds.indexOf(root.selected.id) >= 0 ? "Remove from compare" : "Add to compare"
                                onClicked: root.toggleCompare(root.selected.id) }
                        }
                        Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; radius: Galaxy.radiusPanel; color: Galaxy.card; border.color: Galaxy.line; clip: true

                            // ------------------------------------------------ details
                            Flickable { anchors.fill: parent; anchors.margins: 16; visible: root.page === "models" && !!root.selected; clip: true; contentHeight: det.implicitHeight
                                ColumnLayout { id: det; width: parent.width; spacing: 5
                                    Text { text: root.selected ? root.selected.name : ""; font.family: Galaxy.font; font.pixelSize: 18; color: Galaxy.ink }
                                    Text { Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; font.family: Galaxy.font; font.pixelSize: 12; color: Galaxy.muted
                                        text: root.selected ? (root.selected.notes || "") : "" }
                                    Head { text: "CAN IT RUN HERE" }
                                    KV { k: "GPU fit"; v: root.selected ? root.fitLabel(root.selected.fit) + ": " + root.selected.fit.reason : ""; tint: root.selected ? root.fitColor(root.selected.fit) : Galaxy.ink }
                                    KV { k: "State"; v: root.selected ? (root.selected.runnable ? "ready to run" : "cannot run yet") + (root.selected.local ? " · local" : " · HOSTED: " + root.selected.hosted_service) : ""
                                        tint: root.selected && root.selected.runnable ? Galaxy.ok : Galaxy.warn }
                                    Repeater { model: root.selected ? root.selected.missing : []
                                        ColumnLayout { required property var modelData; Layout.fillWidth: true; spacing: 1
                                            KV { k: "missing " + parent.modelData.kind; v: parent.modelData.what; tint: Galaxy.err }
                                            KV { k: "fix"; v: parent.modelData.fix; tint: Galaxy.lavender } } }
                                    Head { text: "RELEASE" }
                                    KV { k: "Capability"; v: root.selected ? root.selected.capability + " · " + (root.selected.subtasks || []).join(", ") : "" }
                                    KV { k: "Checkpoint"; v: root.selected && root.selected.release ? (root.selected.release.hf_repo || root.selected.release.url || "—") : "" }
                                    KV { k: "Revision"; v: root.selected && root.selected.release ? (root.selected.release.pinned_revision || (root.selected.upstream ? root.selected.upstream.revision + " (upstream, not pinned)" : root.selected.release.revision_status || "unverified")) : ""
                                        tint: root.selected && root.selected.release && root.selected.release.pinned_revision ? Galaxy.ink : Galaxy.warn }
                                    KV { k: "Released"; v: root.selected && root.selected.release ? String(root.selected.release.date || "—") : "" }
                                    KV { visible: !!(root.selected && root.selected.release && root.selected.release.base_model); k: "Base model"
                                        v: root.selected && root.selected.release && root.selected.release.base_model ? root.selected.release.base_model + " · " + (root.selected.release.method || "") : "" }
                                    KV { k: "Licence"; v: root.selected && root.selected.license ? root.selected.license.name + " · " + (root.selected.license.access || "") + (root.selected.license.commercial ? " · commercial: " + root.selected.license.commercial : "") + (root.selected.license.note ? "\n" + root.selected.license.note : "") : "" }
                                    KV { k: "Availability"; v: root.selected ? (root.selected.availability || "weights") : ""; tint: root.selected && (root.selected.availability || "weights") !== "weights" ? Galaxy.warn : Galaxy.ink }
                                    Head { text: "RUNTIME AND MEMORY" }
                                    KV { k: "Runtime"; v: root.selected ? (root.selected.runtime || []).join(" · ") : "" }
                                    KV { k: "Precision"; v: root.selected ? String(root.selected.precision || "—") + " · weights " + (root.selected.weights_gb || "?") + " GB" : "" }
                                    KV { k: "Documented"; v: root.selected && root.selected.memory ? (root.selected.memory.documented || "—") + "  [" + (root.selected.memory.basis || "unknown") + "]" : "" }
                                    KV { k: "Inputs → outputs"; v: root.selected ? (root.selected.inputs || []).join(", ") + "  →  " + (root.selected.outputs || []).join(", ") : "" }
                                    Head { text: "EVIDENCE" }
                                    Repeater { model: root.selected ? (root.selected.benchmarks || []) : []
                                        KV { required property var modelData; k: "published"; v: modelData.metric + ": " + modelData.value + "\n" + modelData.settings + " · " + modelData.date + " · " + modelData.source } }
                                    KV { k: "local"; v: root.selected ? (root.selected.local_benchmarks ? root.selected.local_benchmarks + " measurement(s) on this machine (see Compare)" : "untested on this machine") : ""
                                        tint: root.selected && root.selected.local_benchmarks ? Galaxy.ok : Galaxy.label }
                                    Repeater { model: root.selected ? (root.selected.sources || []) : []
                                        Text { required property string modelData; Layout.fillWidth: true; elide: Text.ElideMiddle; text: "↗ " + modelData; font.family: Galaxy.font; font.pixelSize: 11; color: Galaxy.purple
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["xdg-open", parent.modelData]) } } }
                                }
                            }

                            // ------------------------------------------------ run
                            Flickable { anchors.fill: parent; anchors.margins: 16; visible: root.page === "run" && !!root.selected; clip: true; contentHeight: runCol.implicitHeight
                                ColumnLayout { id: runCol; width: parent.width; spacing: 8
                                    Text { text: root.selected ? "Run " + root.selected.name : ""; font.family: Galaxy.font; font.pixelSize: 16; color: Galaxy.ink }
                                    Rectangle { visible: !!root.selected && !root.selected.runnable; Layout.fillWidth: true; implicitHeight: why.implicitHeight + 20; radius: Galaxy.radiusControl; color: Galaxy.errBg; border.color: Galaxy.err
                                        Text { id: why; anchors.fill: parent; anchors.margins: 10; wrapMode: Text.Wrap; textFormat: Text.PlainText; font.family: Galaxy.font; font.pixelSize: 12; color: Galaxy.ink
                                            text: root.selected ? "This model cannot run here yet.\n" + root.selected.missing.map(m => "• " + m.kind + ": " + m.what + "\n   fix: " + m.fix).join("\n") : "" } }
                                    Rectangle { visible: !!root.selected && !!root.selected.hosted_service; Layout.fillWidth: true; implicitHeight: 44; radius: Galaxy.radiusControl; color: Galaxy.warnBg; border.color: Galaxy.warn
                                        RowLayout { anchors.fill: parent; anchors.margins: 10
                                            CheckBox { checked: root.hostedConfirmed; onToggled: root.hostedConfirmed = checked }
                                            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; font.family: Galaxy.font; font.pixelSize: 12; color: Galaxy.warn
                                                text: root.selected && root.selected.hosted_service ? "HOSTED: this sends your prompt and files to " + root.selected.hosted_service + ". Tick to allow." : "" } } }
                                    Text { visible: !!root.selected && root.selected.capability === "llm"; Layout.fillWidth: true; wrapMode: Text.Wrap; font.family: Galaxy.font; font.pixelSize: 12; color: Galaxy.muted
                                        text: "Language models are used from the Chat page." }
                                    Repeater { model: root.selected ? (root.selected.params || []) : []
                                        ColumnLayout { id: prow; required property var modelData; Layout.fillWidth: true; spacing: 3
                                            Text { text: prow.modelData.name + (prow.modelData.required ? " *" : "") + (prow.modelData.help ? "  ·  " + prow.modelData.help : "")
                                                + (prow.modelData.min !== undefined && prow.modelData.max !== undefined ? "  (" + prow.modelData.min + "–" + prow.modelData.max + ")" : "")
                                                font.family: Galaxy.font; font.pixelSize: 11; color: Galaxy.label }
                                            Input { visible: ["str", "int", "float", "file"].indexOf(prow.modelData.type) >= 0
                                                placeholderText: prow.modelData.type === "file" ? "/path/to/file" : prow.modelData.default !== null && prow.modelData.default !== undefined ? "default: " + prow.modelData.default : ""
                                                text: root.form[prow.modelData.name] !== undefined ? String(root.form[prow.modelData.name]) : ""
                                                validator: prow.modelData.type === "int" ? intV : prow.modelData.type === "float" ? dblV : null
                                                onTextEdited: root.setField(prow.modelData.name, text)
                                                IntValidator { id: intV } DoubleValidator { id: dblV; notation: DoubleValidator.StandardNotation } }
                                            TextArea { visible: prow.modelData.type === "text"; Layout.fillWidth: true; Layout.preferredHeight: 70; wrapMode: TextEdit.Wrap
                                                color: Galaxy.ink; selectionColor: Galaxy.violet; font.family: Galaxy.font; font.pixelSize: 13; padding: 9
                                                text: root.form[prow.modelData.name] !== undefined ? String(root.form[prow.modelData.name]) : ""
                                                onTextChanged: if (activeFocus) root.setField(prow.modelData.name, text)
                                                background: Rectangle { radius: Galaxy.radiusControl; color: Galaxy.base; border.color: parent.activeFocus ? Galaxy.purple : Galaxy.line } }
                                            Flow { visible: prow.modelData.type === "choice"; Layout.fillWidth: true; spacing: 6
                                                Repeater { model: prow.modelData.choices || []
                                                    Chip { required property string modelData; text: modelData
                                                        on: (root.form[prow.modelData.name] !== undefined ? root.form[prow.modelData.name] : prow.modelData.default) === modelData
                                                        onClicked: root.setField(prow.modelData.name, modelData) } } }
                                            Chip { visible: prow.modelData.type === "bool"
                                                readonly property bool val: root.form[prow.modelData.name] !== undefined ? root.form[prow.modelData.name] : !!prow.modelData.default
                                                text: val ? "on" : "off"; on: val; onClicked: root.setField(prow.modelData.name, !val) }
                                        } }
                                    RowLayout { Layout.fillWidth: true; spacing: 10
                                        GalaxyButton { primary: true; text: runProc.running ? "Submitting…" : "Run"; enabled: !!root.selected && root.selected.runnable && root.selected.capability !== "llm" && !runProc.running
                                            onClicked: root.runSelected() }
                                        Text { Layout.fillWidth: true; wrapMode: Text.Wrap; font.family: Galaxy.font; font.pixelSize: 11; color: Galaxy.dim
                                            text: root.activeJobs.length ? "A job is active: this one will queue until the GPU is free." : "Runs locally as a queued job. One GPU job at a time." } }
                                }
                            }

                            // ------------------------------------------------ compare
                            Flickable { anchors.fill: parent; anchors.margins: 16; visible: root.page === "compare"; clip: true; contentHeight: cmp.implicitHeight
                                ColumnLayout { id: cmp; width: parent.width; spacing: 6
                                    Text { visible: !root.compareIds.length; text: "Pick up to three models with “Add to compare”."; font.family: Galaxy.font; font.pixelSize: 12; color: Galaxy.dim }
                                    RowLayout { Layout.fillWidth: true; spacing: 12; visible: root.compareIds.length > 0
                                        Repeater { model: root.compareIds.map(id => root.models.find(m => m.id === id)).filter(m => !!m)
                                            ColumnLayout { id: ccol; required property var modelData; Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; spacing: 4
                                                Text { Layout.fillWidth: true; elide: Text.ElideRight; text: ccol.modelData.name; font.family: Galaxy.font; font.pixelSize: 14; color: Galaxy.ink }
                                                Pill { text: root.fitLabel(ccol.modelData.fit); tint: root.fitColor(ccol.modelData.fit) }
                                                Repeater { model: [["Task", ccol.modelData.capability + " · " + (ccol.modelData.subtasks || []).join(", ")],
                                                                   ["State", root.stateLabel(ccol.modelData)],
                                                                   ["Licence", ccol.modelData.license ? ccol.modelData.license.name : "—"],
                                                                   ["Released", ccol.modelData.release ? String(ccol.modelData.release.date || "—") : "—"],
                                                                   ["Precision", String(ccol.modelData.precision || "—")],
                                                                   ["Weights", (ccol.modelData.weights_gb || "?") + " GB"],
                                                                   ["VRAM resident", ccol.modelData.memory && ccol.modelData.memory.gpu_resident_gb ? ccol.modelData.memory.gpu_resident_gb + " GB (" + (ccol.modelData.fit.basis) + ")" : "unknown"],
                                                                   ["VRAM offload", ccol.modelData.memory && ccol.modelData.memory.gpu_offload_gb ? ccol.modelData.memory.gpu_offload_gb + " GB" : "unknown"],
                                                                   ["Measured peak", ccol.modelData.fit.peak_vram_gb ? ccol.modelData.fit.peak_vram_gb + " GB (measured here)" : "untested here"],
                                                                   ["Local runs", String(ccol.modelData.local_benchmarks)]]
                                                    ColumnLayout { required property var modelData; Layout.fillWidth: true; spacing: 0
                                                        Text { text: parent.modelData[0]; font.family: Galaxy.font; font.pixelSize: 10; color: Galaxy.label }
                                                        Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: parent.modelData[1]; font.family: Galaxy.font; font.pixelSize: 12; color: Galaxy.ink } } }
                                                Text { text: "Published"; font.family: Galaxy.font; font.pixelSize: 10; color: Galaxy.label }
                                                Repeater { model: ccol.modelData.benchmarks || []
                                                    Text { required property var modelData; Layout.fillWidth: true; wrapMode: Text.Wrap; font.family: Galaxy.font; font.pixelSize: 11; color: Galaxy.muted
                                                        text: modelData.metric + ": " + modelData.value + "\n(" + modelData.settings + "; " + modelData.date + ")" } }
                                                Text { visible: !(ccol.modelData.benchmarks || []).length; text: "none recorded"; font.family: Galaxy.font; font.pixelSize: 11; color: Galaxy.dim }
                                                GalaxyButton { text: "Remove"; onClicked: root.toggleCompare(ccol.modelData.id) }
                                            } } }
                                    Text { visible: root.compareIds.length > 0; Layout.fillWidth: true; wrapMode: Text.Wrap; font.family: Galaxy.font; font.pixelSize: 10; color: Galaxy.dim; topPadding: 8
                                        text: "Published numbers keep their own settings and are not comparable with each other. For like-for-like local numbers run: ai-media bench run MODEL… (same fixture, one model at a time)." }
                                }
                            }

                            // ------------------------------------------------ chat
                            ColumnLayout { anchors.fill: parent; anchors.margins: 16; visible: root.page === "chat"; spacing: 8
                                Flow { Layout.fillWidth: true; spacing: 6
                                    Repeater { model: root.llm.models || []
                                        Chip { required property var modelData; text: modelData.ref + (modelData.quantization ? " · " + modelData.quantization : ""); on: root.chatModel === modelData.ref
                                            onClicked: { root.chatModel = modelData.ref } } }
                                    Text { visible: !(root.llm.models || []).length; font.family: Galaxy.font; font.pixelSize: 12; color: Galaxy.warn; width: parent.width; wrapMode: Text.Wrap
                                        text: "No local LLM server is answering. Start one:  ollama serve   or   llama-server -m MODEL.gguf -ngl 99 -c 16384 --jinja"
                                            + ((root.llm.gguf_on_disk || []).length ? "\nGGUF files on disk: " + root.llm.gguf_on_disk.map(g => g.path).join(", ") : "") } }
                                RowLayout { Layout.fillWidth: true; spacing: 14
                                    component Knob: RowLayout { property string label: ""; property alias from: sl.from; property alias to: sl.to; property alias step: sl.stepSize; property alias value: sl.value; property int digits: 0
                                        signal moved(real v); spacing: 6
                                        Text { text: parent.label + " " + sl.value.toFixed(parent.digits); font.family: Galaxy.font; font.pixelSize: 10; color: Galaxy.label; Layout.preferredWidth: 104 }
                                        Slider { id: sl; Layout.preferredWidth: 90; onMoved: parent.moved(value) } }
                                    Knob { label: "temperature"; from: 0; to: 2; step: 0.05; digits: 2; value: root.temperature; onMoved: v => root.temperature = v }
                                    Knob { label: "max tokens"; from: 32; to: 4096; step: 32; value: root.maxTokens; onMoved: v => root.maxTokens = v }
                                    Knob { label: "context"; from: 2048; to: 131072; step: 2048; value: root.contextLen; onMoved: v => root.contextLen = v }
                                    Knob { label: "GPU layers"; from: -1; to: 99; step: 1; value: root.gpuLayers; onMoved: v => root.gpuLayers = v }
                                }
                                Text { Layout.fillWidth: true; font.family: Galaxy.font; font.pixelSize: 10; color: Galaxy.dim; wrapMode: Text.Wrap
                                    text: "Context and GPU layers apply per request on Ollama (-1 = all layers). A llama.cpp server fixes both when it starts; its real context is shown after each reply." }
                                ListView { id: chatView; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 8; boundsBehavior: Flickable.StopAtBounds
                                    model: root.chatMessages.concat(root.chatPartial.length || chatProc.running ? [{ role: "assistant", content: root.chatPartial + "▌" }] : [])
                                    onCountChanged: positionViewAtEnd()
                                    delegate: Rectangle { id: bub; required property var modelData
                                        width: chatView.width; height: bt.implicitHeight + 18; radius: Galaxy.radiusControl
                                        color: modelData.role === "user" ? Galaxy.raised : Galaxy.tile; border.color: modelData.role === "user" ? Galaxy.edge : Galaxy.line
                                        Text { id: bt; anchors.fill: parent; anchors.margins: 9; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: bub.modelData.content
                                            font.family: Galaxy.font; font.pixelSize: 13; color: bub.modelData.role === "user" ? Galaxy.lavender : Galaxy.ink } } }
                                Text { visible: !!root.chatStats; font.family: Galaxy.mono; font.pixelSize: 11; color: Galaxy.label
                                    text: root.chatStats ? "TTFT " + root.chatStats.ttft_s + " s · prompt " + (root.chatStats.prompt_tps || "?") + " tok/s · generation " + (root.chatStats.gen_tps || "?") + " tok/s · "
                                        + (root.chatStats.gen_tokens || "?") + " tokens · context " + (root.chatStats.context || "?") : "" }
                                RowLayout { Layout.fillWidth: true; spacing: 8
                                    Input { id: chatIn; placeholderText: root.chatModel.length ? "Message " + root.chatModel + "…  (Enter to send)" : "No model selected"; enabled: !chatProc.running
                                        onAccepted: { root.sendChat(text); text = "" } }
                                    GalaxyButton { visible: !chatProc.running; primary: true; text: "Send"; onClicked: { root.sendChat(chatIn.text); chatIn.text = "" } }
                                    GalaxyButton { visible: chatProc.running; danger: true; text: "Stop"; onClicked: root.stopChat() }
                                    GalaxyButton { text: "Clear"; onClicked: root.clearChat() } }
                            }

                            // ------------------------------------------------ jobs
                            ListView { id: jobList; anchors.fill: parent; anchors.margins: 16; visible: root.page === "jobs"; clip: true; spacing: 8; boundsBehavior: Flickable.StopAtBounds
                                model: root.jobs
                                delegate: Rectangle { id: jrow; required property var modelData
                                    readonly property bool active: ["queued", "waiting-gpu", "running", "cancelling"].indexOf(modelData.status) >= 0
                                    width: jobList.width; height: jc.implicitHeight + 20; radius: Galaxy.radiusControl; color: Galaxy.tile
                                    border.color: modelData.status === "failed" ? Galaxy.err : active ? Galaxy.purple : Galaxy.line
                                    ColumnLayout { id: jc; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10; spacing: 5
                                        RowLayout { Layout.fillWidth: true; spacing: 8
                                            Text { text: jrow.modelData.model; font.family: Galaxy.font; font.pixelSize: 13; color: Galaxy.ink }
                                            Pill { text: jrow.modelData.status; tint: jrow.modelData.status === "completed" ? Galaxy.ok : jrow.modelData.status === "failed" ? Galaxy.err : jrow.active ? Galaxy.warn : Galaxy.label }
                                            Pill { visible: !!jrow.modelData.mock; text: "MOCK · not inference"; tint: Galaxy.magenta }
                                            Text { text: jrow.modelData.job_id; font.family: Galaxy.mono; font.pixelSize: 10; color: Galaxy.dim }
                                            Item { Layout.fillWidth: true }
                                            Text { visible: jrow.modelData.runtime_s !== null && jrow.modelData.runtime_s !== undefined; font.family: Galaxy.mono; font.pixelSize: 11; color: Galaxy.label
                                                text: jrow.modelData.runtime_s + " s" + (jrow.modelData.peak_vram_gb ? " · peak " + jrow.modelData.peak_vram_gb + " GB" : "") }
                                            GalaxyButton { visible: jrow.active; danger: true; text: "Cancel"; onClicked: root.jobAction("cancel", jrow.modelData.job_id) }
                                            GalaxyButton { visible: jrow.modelData.status === "completed"; text: "Open"; onClicked: root.jobAction("open", jrow.modelData.job_id) }
                                            GalaxyButton { visible: jrow.modelData.status === "completed"; text: "Folder"; onClicked: root.jobAction("folder", jrow.modelData.job_id) } }
                                        Rectangle { visible: jrow.active; Layout.fillWidth: true; implicitHeight: 6; radius: 3; color: Galaxy.base
                                            Rectangle { height: parent.height; radius: 3; color: Galaxy.purple; width: parent.width * Math.max(0.02, ((jrow.modelData.progress || {}).pct || 0) / 100)
                                                Behavior on width { NumberAnimation { duration: Galaxy.slow } } } }
                                        Text { visible: jrow.active; font.family: Galaxy.font; font.pixelSize: 11; color: Galaxy.label
                                            text: (jrow.modelData.queue_reason || (jrow.modelData.progress || {}).stage || "") + " · " + ((jrow.modelData.progress || {}).pct || 0) + "%" }
                                        Text { visible: (jrow.modelData.outputs || []).length > 0; Layout.fillWidth: true; elide: Text.ElideMiddle; font.family: Galaxy.mono; font.pixelSize: 11; color: Galaxy.ok
                                            text: (jrow.modelData.outputs || []).join("  ") }
                                        Text { visible: !!jrow.modelData.error; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; font.family: Galaxy.font; font.pixelSize: 11; color: Galaxy.err
                                            text: jrow.modelData.error ? jrow.modelData.error.message + (jrow.modelData.error.hint ? "\nWhat to do: " + jrow.modelData.error.hint : "") : "" }
                                    } }
                                Text { anchors.centerIn: parent; visible: !root.jobs.length; text: "No jobs yet"; font.family: Galaxy.font; font.pixelSize: 12; color: Galaxy.dim }
                            }
                        }
                    }
                }
                Text { Layout.fillWidth: true; visible: root.notice.length > 0; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: root.notice
                    font.family: Galaxy.font; font.pixelSize: 12; color: root.noticeIsError ? Galaxy.err : Galaxy.ok }
            }
        }
    }
}
