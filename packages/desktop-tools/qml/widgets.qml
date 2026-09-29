//@ pragma ShellId zionsec-tools-widgets
//@ pragma DataDir $BASE/zionsec-tools
//@ pragma StateDir $BASE/zionsec-tools

// Desktop widgets for NixOS Updater and Storage Optimizer (plus the session's
// polkit password prompt), drawn as a small
// layer-shell strip in the empty part of Ambxst's bar (right of the
// workspaces). Independent of Ambxst's mod system: this is its own Quickshell
// instance, started by the zionsec-tools-widgets user service.
//
// Placement comes from the service environment (set declaratively by the
// NixOS module): ZS_WIDGETS_SIDE=left|right, ZS_WIDGETS_OFFSET=<px>,
// ZS_WIDGETS_TOP=<px>, ZS_WIDGETS_SHOW=updater,storage.

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs.shared
import qs.updater
import qs.storage
import qs.polkit

ShellRoot {
    id: shell
    readonly property string side: Quickshell.env("ZS_WIDGETS_SIDE") || "left"
    readonly property int offset: parseInt(Quickshell.env("ZS_WIDGETS_OFFSET") || "416")
    readonly property int top: parseInt(Quickshell.env("ZS_WIDGETS_TOP") || "4")
    readonly property var show: (Quickshell.env("ZS_WIDGETS_SHOW") || "updater,storage").split(",")

    // Polkit authentication agent + password prompt for the whole session
    // (replaces hyprpolkitagent's plain dialog). Not affected by the hiding
    // below: an authentication request is always shown.
    PolkitPrompt {}

    // Follow Ambxst's bar: hide whenever the bar auto-hides, which Ambxst does
    // when the bar is unpinned or the focused window is fullscreen
    // (BarContent.qml: shouldAutoHide = !pinned || activeWindowFullscreen).
    // Pinning is saved to bar.json ("pinnedOnStartup"), which is watched; the
    // fullscreen check is the same native toplevel check Ambxst uses.
    property bool barPinned: true
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ambxst/config/bar.json"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const b = JSON.parse(text());
                shell.barPinned = b.pinnedOnStartup !== undefined ? b.pinnedOnStartup === true : true;
            } catch (e) {}
        }
    }
    readonly property bool fullscreen: {
        const t = ToplevelManager.activeToplevel;
        return !!t && t.activated && t.fullscreen === true;
    }
    readonly property bool stripShown: barPinned && !fullscreen

    // Ambxst draws its bar on an Overlay-layer surface too. Within a layer the
    // newest surface is on top, so when Ambxst (re)creates its surface after
    // ours — at login or on `ambxst reload` — recreate the strip so it stays
    // above the bar instead of disappearing behind it.
    property bool stripActive: true
    signal toggleRequested(string name)

    // `quickshell ipc -p <widgets.qml> call widgets toggle updater|storage`
    // — bindable to a key in Hyprland.
    IpcHandler {
        target: "widgets"
        function toggle(name: string): void { shell.toggleRequested(name); }
    }
    Timer {
        id: restack
        interval: 1200
        onTriggered: { shell.stripActive = false; Qt.callLater(() => shell.stripActive = true); }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openlayer" && event.data.startsWith("ambxst")) restack.restart();
        }
    }

    Variants {
        model: shell.stripActive ? Quickshell.screens : []

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData

            // Fade out, then unmap (no input region left behind). Mapping it
            // again creates a new surface, which also restacks it above the bar.
            visible: shell.stripShown || row.opacity > 0

            anchors.top: true
            anchors.left: shell.side === "left"
            anchors.right: shell.side === "right"
            margins.top: shell.top
            margins.left: shell.side === "left" ? shell.offset : 0
            margins.right: shell.side === "right" ? shell.offset : 0

            // Sits over Ambxst's bar; reserves no space and takes no keyboard focus.
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "zionsec-tools"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            implicitWidth: row.implicitWidth
            implicitHeight: 36

            Connections {
                target: shell
                function onToggleRequested(name) {
                    if (panel.modelData !== Quickshell.screens[0]) return;
                    if (name === "updater") { sto.popupOpen = false; upd.popupOpen = !upd.popupOpen; }
                    else if (name === "storage") { upd.popupOpen = false; sto.popupOpen = !sto.popupOpen; }
                }
            }

            Connections {
                target: shell
                function onStripShownChanged() {
                    if (!shell.stripShown) { upd.popupOpen = false; sto.popupOpen = false; }
                }
            }

            Row {
                id: row
                spacing: 5
                opacity: shell.stripShown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.anim / 2; easing.type: Easing.OutCubic } }
                UpdaterWidget {
                    id: upd
                    visible: shell.show.indexOf("updater") >= 0
                    onRequestExclusive: sto.popupOpen = false
                }
                StorageWidget {
                    id: sto
                    visible: shell.show.indexOf("storage") >= 0
                    onRequestExclusive: upd.popupOpen = false
                }
            }
        }
    }
}
