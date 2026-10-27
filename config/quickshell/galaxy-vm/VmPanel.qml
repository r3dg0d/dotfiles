import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// One Construct app window: Android / Windows / Linux, or the "all" manager.
FloatingWindow {
    id: win
    required property string kind          // windows | linux | android | all
    required property var app              // root ShellRoot (state, run(), term())
    property bool opened: false
    visible: opened
    onClosed: opened = false
    readonly property var meta: ({
        windows: { title: "Windows Construct", icon: "galaxy-windows", backend: "QEMU/KVM · libvirt (session)", tool: "windowsvm" },
        linux:   { title: "Linux Construct",   icon: "galaxy-linux",   backend: "QEMU/KVM · libvirt (session)", tool: "linuxvm" },
        android: { title: "Android Construct", icon: "galaxy-android", backend: "Docker-Android-Pro · rootless Docker", tool: "androidvm" },
        ios:     { title: "iOS Construct",     icon: "galaxy-ios",     backend: "qemu-sptm -M darwin (darwin-vm) · serial root shell", tool: "iosvm" },
        macos:   { title: "macOS Construct",   icon: "galaxy-macos",   backend: "QEMU/KVM + OpenCore · or Docker-OSX", tool: "macosvm" },
        all:     { title: "VM Construct",      icon: "galaxy-vm-construct", backend: "vmtools suite", tool: "vmtools" } })[kind]
    title: "Galaxy " + meta.title
    implicitWidth: kind === "all" ? 620 : 600; implicitHeight: 760
    minimumSize: Qt.size(480, 520)
    color: "transparent"   // Nebula paints the solid #0e0a1c fill; niri clips to the 22px radius
    readonly property var vms: (app.st.vms || []).filter(v => kind === "all" || v.kind === kind)
    readonly property var checks: kind === "all" ? [] : ((app.st.checks || {})[kind] || [])
    readonly property int fails: checks.filter(c => !c.ok).length
    property bool wizard: false
    property bool logOpen: false
    property var logLines: []
    function fmtUp(s) { if (s === null || s === undefined) return "—"; s = Math.floor(s); const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60); return (h ? h + "h " : "") + m + "m" }
    function refreshLog() { if (kind !== "all") { logProc.command = ["python3", Quickshell.shellPath("vm.py"), "log", kind, "30"]; logProc.running = true } }
    Process { id: logProc; stdout: StdioCollector { onStreamFinished: { try { win.logLines = JSON.parse(text).lines } catch (e) {} } } }
    Timer { interval: 4000; repeat: true; running: win.opened; triggeredOnStart: true; onTriggered: win.refreshLog() }

    Nebula { anchors.fill: parent; radius: 22; seed: win.kind.length * 13 }
    Flickable {
        anchors.fill: parent; anchors.margins: 20; contentHeight: col.implicitHeight; clip: true
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: col; width: parent.width; spacing: 14

            // ---- header (drag to move) ----
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                Image { source: Quickshell.iconPath(win.meta.icon, true); sourceSize: Qt.size(40, 40); Layout.preferredWidth: 40; Layout.preferredHeight: 40 }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Text { text: "✦  " + win.meta.title.toUpperCase().split("").join(" "); font.family: "Cellforge"; font.pixelSize: 12; color: "#d4b8ff" }
                    Text { text: win.meta.backend + "  ·  " + (app.updated || "…"); font.family: "Cellforge"; font.pixelSize: 10; color: "#8a84a8" }
                }
                GalaxyButton { text: "󰑐"; hint: "Refresh"; onClicked: { app.refresh(); win.refreshLog() } }
                GalaxyButton { text: "×"; hint: "Close (VMs keep running)"; onClicked: win.opened = false }
            }
            // ---- manager: per-kind overview ----
            Repeater {
                model: win.kind === "all" ? ["android", "windows", "linux", "ios", "macos"] : []
                Rectangle {
                    required property string modelData
                    readonly property var sub: (app.st.vms || []).filter(v => v.kind === modelData)
                    readonly property var subChecks: ((app.st.checks || {})[modelData] || [])
                    Layout.fillWidth: true; implicitHeight: 76; radius: 16; color: "#110d20"; border.color: "#2a2344"
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 14; spacing: 12
                        Image { source: Quickshell.iconPath("galaxy-" + modelData, true); sourceSize: Qt.size(42, 42) }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 3
                            Text { text: (({ ios: "iOS", macos: "macOS" })[modelData] || (modelData.charAt(0).toUpperCase() + modelData.slice(1))) + " Construct"; font.family: "Cellforge"; font.pixelSize: 14; color: "#f2f0ff" }
                            Text { font.family: "Cellforge"; font.pixelSize: 10; color: "#9a96b3"
                                text: parent.parent.parent.sub.length + " VM" + (parent.parent.parent.sub.length === 1 ? "" : "s") + " · "
                                      + parent.parent.parent.sub.filter(v => v.state === "running").length + " running · "
                                      + parent.parent.parent.subChecks.filter(c => !c.ok).length + " check(s) failing" }
                        }
                        GalaxyButton { text: "Open"; primary: true; onClicked: app.openKind(modelData) }
                    }
                }
            }
            RowLayout {
                visible: win.kind === "all"; Layout.fillWidth: true; spacing: 8
                GalaxyButton { text: "󰙨 vmtools doctor"; onClicked: app.term("vmtools doctor") }
                GalaxyButton { text: "󰆍 TUI"; onClicked: app.term("vmtools tui") }
                Item { Layout.fillWidth: true }
                Text { text: (app.st.docker ? "DOCKER UP" : "DOCKER OFFLINE"); font.family: "Cellforge"; font.pixelSize: 10; color: app.st.docker ? "#7dffa8" : "#ffd479" }
            }

            // ---- VM cards ----
            Text { visible: win.kind !== "all" || win.vms.length > 0; text: "VIRTUAL MACHINES"; font.family: "Cellforge"; font.pixelSize: 10; color: "#8a84a8"; font.letterSpacing: 2 }
            Text { visible: win.vms.length === 0 && win.kind !== "all"; text: "No " + win.meta.title + " VMs yet — create one below."; font.family: "Cellforge"; font.pixelSize: 12; color: "#9a96b3" }
            Repeater {
                model: win.vms
                Rectangle {
                    id: card
                    required property var modelData
                    readonly property bool running: modelData.state === "running"
                    Layout.fillWidth: true; implicitHeight: cardCol.implicitHeight + 24; radius: 16
                    color: "#110d20"; border.color: running ? "#5b3d99" : "#2a2344"
                    ColumnLayout {
                        id: cardCol; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 } spacing: 8
                        RowLayout {
                            spacing: 8
                            Rectangle { width: 9; height: 9; radius: 5; color: card.running ? "#7dffa8" : modelData.state === "paused" ? "#ffd479" : "#5d5878" }
                            Text { text: modelData.name; font.family: "Cellforge"; font.pixelSize: 15; color: "#f2f0ff"; Layout.fillWidth: true }
                            Text { text: String(modelData.state).toUpperCase(); font.family: "Cellforge"; font.pixelSize: 10; color: card.running ? "#7dffa8" : "#9a96b3" }
                        }
                        RowLayout {
                            spacing: 18
                            Repeater {
                                model: [["CPU", modelData.cpu_pct === null || modelData.cpu_pct === undefined ? "—" : modelData.cpu_pct + "%"],
                                        ["VCPU", modelData.cpus || "—"],
                                        ["RAM", modelData.ram_mb ? (modelData.ram_mb / 1024).toFixed(1) + "G" : "—"],
                                        ["UP", win.fmtUp(modelData.uptime_s)]]
                                Column { required property var modelData; spacing: 2
                                    Text { text: modelData[0]; font.family: "Cellforge"; font.pixelSize: 9; color: "#8a84a8" }
                                    Text { text: modelData[1]; font.family: "Zerodot"; font.pixelSize: 15; color: "#d4b8ff" } }
                            }
                            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: modelData.detail || ""; font.family: "Cellforge"; font.pixelSize: 10; color: "#5d5878"; elide: Text.ElideLeft }
                        }
                        Flow {
                            Layout.fillWidth: true; spacing: 6
                            GalaxyButton { text: "󰐊 Start"; visible: !card.running; onClicked: app.act(modelData.kind, "start", modelData.name) }
                            GalaxyButton { text: "󰓛 Stop"; visible: card.running; hint: modelData.kind === "android" ? "docker stop" : "force stop (use Shutdown for a clean ACPI shutdown)"; onClicked: app.act(modelData.kind, "stop", modelData.name) }
                            GalaxyButton { text: "󰐥 Shutdown"; visible: card.running && modelData.kind !== "android"; onClicked: app.act(modelData.kind, "shutdown", modelData.name) }
                            GalaxyButton { text: "󰜉 Restart"; visible: card.running; onClicked: app.act(modelData.kind, "restart", modelData.name) }
                            GalaxyButton { text: "󰍹 " + modelData.display; enabled: card.running || modelData.kind !== "android"
                                hint: modelData.kind === "android" ? (modelData.viewer || "") : "virt-viewer / virt-manager"
                                onClicked: modelData.kind === "android" && modelData.viewer ? Qt.openUrlExternally(modelData.viewer) : app.act(modelData.kind, "gui", modelData.name) }
                            GalaxyButton { text: "󰄛 adb shell"; visible: modelData.kind === "android" && card.running; onClicked: app.term("androidvm shell " + modelData.name) }
                            GalaxyButton { text: "󰋽 Info"; onClicked: app.term(win.meta.tool + " info " + modelData.name) }
                        }
                    }
                }
            }

            // ---- create / setup wizard ----
            Rectangle {
                visible: win.kind !== "all"
                Layout.fillWidth: true; implicitHeight: wz.implicitHeight + 24; radius: 16; color: "#0f0b1c"; border.color: win.wizard ? "#b46bff" : "#2a2344"
                ColumnLayout {
                    id: wz; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 } spacing: 10
                    RowLayout {
                        Text { text: "✚  NEW " + win.meta.title.toUpperCase(); font.family: "Cellforge"; font.pixelSize: 11; color: "#d4b8ff"; Layout.fillWidth: true }
                        GalaxyButton { text: win.wizard ? "Hide" : "Create…"; primary: !win.wizard; onClicked: win.wizard = !win.wizard }
                    }
                    GridLayout {
                        visible: win.wizard; columns: 2; columnSpacing: 10; rowSpacing: 8; Layout.fillWidth: true
                        Text { text: "Name"; font.family: "Cellforge"; color: "#9a96b3"; font.pixelSize: 11 }
                        TextField { id: fName; Layout.fillWidth: true; placeholderText: ({ android: "pixel", windows: "win11", ios: "iphone", macos: "mac" })[win.kind] || "fedora"; font.family: "Cellforge" }
                        Text { visible: win.kind === "linux"; text: "Distro"; font.family: "Cellforge"; color: "#9a96b3"; font.pixelSize: 11 }
                        ComboBox { id: fDistro; visible: win.kind === "linux"; Layout.fillWidth: true; model: ["fedora", "ubuntu", "debian", "arch", "nixos", "mint", "kali", "opensuse", "cachyos"]; font.family: "Cellforge" }
                        Text { visible: win.kind === "android"; text: "Image tag"; font.family: "Cellforge"; color: "#9a96b3"; font.pixelSize: 11 }
                        ComboBox { id: fTag; visible: win.kind === "android"; Layout.fillWidth: true; editable: true
                            model: ["emulator_16.0_v3.8.0-p1", "emulator_17.0_v3.8.0-p1", "emulator_15.0_v3.8.0-p1", "emulator_14.0_v3.8.0-p1", "emulator_headless_16.0_v3.8.0-p1"]; font.family: "Cellforge" }
                        Text { visible: win.kind === "android"; text: "Device"; font.family: "Cellforge"; color: "#9a96b3"; font.pixelSize: 11 }
                        TextField { id: fDevice; visible: win.kind === "android"; Layout.fillWidth: true; text: "Samsung Galaxy S10"; font.family: "Cellforge" }
                        Text { visible: win.kind === "macos"; text: "Version / backend"; font.family: "Cellforge"; color: "#9a96b3"; font.pixelSize: 11 }
                        RowLayout { visible: win.kind === "macos"; spacing: 6
                            ComboBox { id: fMacVer; model: ["sonoma", "sequoia", "tahoe", "ventura", "monterey", "big-sur", "catalina"]; font.family: "Cellforge" }
                            ComboBox { id: fMacBackend; model: ["qemu", "docker-osx"]; font.family: "Cellforge" } }
                        Text { visible: win.kind === "ios" || win.kind === "macos"; text: "Import file/folder"; font.family: "Cellforge"; color: "#9a96b3"; font.pixelSize: 11 }
                        RowLayout { visible: win.kind === "ios" || win.kind === "macos"; spacing: 6; Layout.fillWidth: true
                            TextField { id: fImport; Layout.fillWidth: true; font.family: "Cellforge"
                                placeholderText: win.kind === "ios" ? "~/Mac/darwin-vm/firmware  or  *.ipsw" : "BaseSystem.dmg · installer .img/.app/.pkg · OpenCore · OVMF" }
                            GalaxyButton { text: "󰋺 Import"; enabled: fImport.text.length > 0
                                onClicked: app.term(win.meta.tool + " import '" + fImport.text.replace(/'/g, "'\\''") + "'") } }
                        Text { visible: win.kind !== "android" && win.kind !== "ios"; text: "vCPU / RAM GiB / Disk GiB"; font.family: "Cellforge"; color: "#9a96b3"; font.pixelSize: 11 }
                        RowLayout { visible: win.kind !== "android" && win.kind !== "ios"; spacing: 6
                            SpinBox { id: fCpu; from: 1; to: 24; value: 4 } SpinBox { id: fRam; from: 2; to: 64; value: 8 } SpinBox { id: fDisk; from: 20; to: 512; value: win.kind === "windows" ? 80 : win.kind === "macos" ? 128 : 40 } }
                        Text { visible: win.kind !== "android" && win.kind !== "ios" && win.kind !== "macos"; text: "ISO (optional)"; font.family: "Cellforge"; color: "#9a96b3"; font.pixelSize: 11 }
                        TextField { id: fIso; visible: win.kind !== "android" && win.kind !== "ios" && win.kind !== "macos"; Layout.fillWidth: true; placeholderText: "auto: download / cached media"; font.family: "Cellforge" }
                    }
                    RowLayout {
                        visible: win.wizard; spacing: 8
                        GalaxyButton {
                            text: "󰐕 Create in terminal"; primary: true; enabled: fName.text.length > 0 || fName.placeholderText.length > 0
                            onClicked: {
                                const n = fName.text || fName.placeholderText
                                const q = s => "'" + String(s).replace(/'/g, "'\\''") + "'"
                                let c
                                if (win.kind === "android") c = "androidvm create --name " + q(n) + " --tag " + q(fTag.editText || fTag.currentText) + " --device " + q(fDevice.text) + " -y"
                                else if (win.kind === "linux") c = "linuxvm create --name " + q(n) + " --distro " + fDistro.currentText + " --cpus " + fCpu.value + " --ram " + fRam.value + " --disk " + fDisk.value + (fIso.text ? " --iso " + q(fIso.text) : "") + " -y"
                                else if (win.kind === "ios") c = "iosvm create --name " + q(n)
                                else if (win.kind === "macos") c = "macosvm create --name " + q(n) + " --version " + fMacVer.currentText + " --backend " + fMacBackend.currentText + " --cpus " + fCpu.value + " --ram " + fRam.value + " --disk " + fDisk.value
                                else c = "windowsvm create --name " + q(n) + " --cpus " + fCpu.value + " --ram " + fRam.value + " --disk " + fDisk.value + (fIso.text ? " --iso " + q(fIso.text) : "")
                                app.term(c)
                            }
                        }
                        GalaxyButton { visible: win.kind === "android"; text: "󰒓 Pro setup"; hint: "docker login + pull + androidvm setup (~/rice-staging/android-pro-setup.sh)"; onClicked: app.term("bash ~/rice-staging/android-pro-setup.sh") }
                        GalaxyButton { visible: win.kind === "windows"; text: "󰗮 ISO cache"; onClicked: app.term("windowsvm iso list") }
                        GalaxyButton { visible: win.kind === "linux"; text: "󰗮 Distros"; onClicked: app.term("linuxvm distro list") }
                    }
                }
            }

            // ---- host checks ----
            RowLayout {
                visible: win.kind !== "all"; Layout.fillWidth: true
                Text { text: "HOST CHECKS"; font.family: "Cellforge"; font.pixelSize: 10; color: "#8a84a8"; font.letterSpacing: 2; Layout.fillWidth: true }
                Text { text: win.fails ? win.fails + " failing" : "all OK"; font.family: "Cellforge"; font.pixelSize: 10; color: win.fails ? "#ff8fb1" : "#7dffa8" }
            }
            Repeater {
                model: win.checks
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true; implicitHeight: chkRow.implicitHeight + 12; radius: 10
                    color: modelData.ok ? "transparent" : "#120e22"
                    RowLayout {
                        id: chkRow; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 8; anchors.rightMargin: 6; spacing: 10
                        Text { text: modelData.ok ? "✓" : modelData.warn ? "!" : "✗"; font.family: "Cellforge"; font.pixelSize: 13; Layout.alignment: Qt.AlignTop; Layout.preferredWidth: 14; horizontalAlignment: Text.AlignHCenter
                            color: modelData.ok ? "#7dffa8" : modelData.warn ? "#ffd479" : "#ff8fb1" }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 2
                            Text { text: modelData.name; font.family: "Cellforge"; font.pixelSize: 12; color: "#f2f0ff"; Layout.fillWidth: true; wrapMode: Text.Wrap }
                            Text { id: det; text: modelData.detail || ""; visible: text.length > 0; font.family: "Cellforge"; font.pixelSize: 10; color: "#8a84a8"
                                Layout.fillWidth: true; elide: Text.ElideMiddle; maximumLineCount: 1
                                HoverHandler { id: detHover }
                                ToolTip.visible: detHover.hovered && det.truncated; ToolTip.text: det.text; ToolTip.delay: 400 }
                        }
                        GalaxyButton { visible: !modelData.ok && !!modelData.fix; implicitHeight: 26; Layout.alignment: Qt.AlignVCenter
                            text: modelData.fix && modelData.fix[0] === "info" ? "How" : "Fix"
                            hint: modelData.fix ? modelData.fix[1] : ""
                            onClicked: modelData.fix[0] === "term" ? app.term(modelData.fix[1]) : app.toast(modelData.fix[1]) }
                    }
                }
            }

            // ---- log tail ----
            Text { visible: win.kind !== "all"; text: (win.logOpen ? "▾" : "▸") + "  LOG  ·  ~/.local/share/vmtools/logs/gui-" + win.kind + ".log"
                font.family: "Cellforge"; font.pixelSize: 10; color: "#8a84a8"; font.letterSpacing: 1; elide: Text.ElideMiddle; Layout.fillWidth: true
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.logOpen = !win.logOpen } }
            Rectangle {
                visible: win.kind !== "all" && win.logOpen; Layout.fillWidth: true; implicitHeight: 130; radius: 12; color: "#05040a"; border.color: "#1d1833"; clip: true
                Text { anchors.fill: parent; anchors.margins: 10; text: win.logLines.slice(-9).join("\n"); font.family: "NullType"; font.pixelSize: 11; color: "#a99fd0"; verticalAlignment: Text.AlignBottom; elide: Text.ElideLeft; wrapMode: Text.NoWrap }
            }
            Text { visible: app.toastText.length > 0; Layout.fillWidth: true; wrapMode: Text.Wrap; text: app.toastText; font.family: "Cellforge"; font.pixelSize: 11; color: "#ffd479" }
        }
    }
    // drag anywhere on empty space of the window header area
    MouseArea { x: 0; y: 0; width: parent.width - 120; height: 70; acceptedButtons: Qt.LeftButton; cursorShape: Qt.SizeAllCursor; onPressed: win.startSystemMove() }
}
