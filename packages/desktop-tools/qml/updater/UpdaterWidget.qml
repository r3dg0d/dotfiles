import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.shared

// Bar pill: update count / state at a glance; click for a compact popup.
// The full administrative UI is the NixOS Updater app, not this popup.
Item {
    id: root
    property alias popupOpen: popup.visible
    signal requestExclusive()

    readonly property var st: UpdaterState.status
    readonly property string state: UpdaterState.state
    readonly property int count: UpdaterState.updateCount

    implicitHeight: 36
    implicitWidth: pillRow.implicitWidth + 24

    function stateText() {
        if (UpdaterState.running) return UpdaterState.phase || "Updating…";
        switch (state) {
        case "checking": return "Checking…";
        case "updates": return count + (count === 1 ? " update" : " updates");
        case "reboot": return "Reboot";
        case "error": return "Check failed";
        case "unknown": return "Not checked";
        default: return "Up to date";
        }
    }
    readonly property color accent: state === "error" ? Theme.error : state === "reboot" ? Theme.warning : Theme.primary

    Surface {
        anchors.fill: parent
        borderColor: ma.containsMouse || popup.visible ? root.accent : Theme.border
        Rectangle { anchors.fill: parent; color: root.accent; opacity: ma.pressed ? 0.2 : (ma.containsMouse ? 0.08 : 0) }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 8
            Spinner { visible: root.state === "checking" || UpdaterState.running; size: 16; anchors.verticalCenter: parent.verticalCenter }
            Icon {
                visible: !(root.state === "checking" || UpdaterState.running)
                icon: root.state === "updates" ? Theme.iDown : root.state === "reboot" ? Theme.iSync
                    : root.state === "error" ? Theme.iAlert : Theme.iCube
                color: root.accent
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                text: root.stateText()
                font.bold: true
                color: root.state === "updates" || root.state === "error" || root.state === "reboot" ? root.accent : Theme.fg
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: m => {
            if (m.button === Qt.MiddleButton) { UpdaterState.openApp(); return; }
            if (!popup.visible) { root.requestExclusive(); UpdaterState.refreshLocal(); }
            popup.visible = !popup.visible;
        }
    }

    PopupWindow {
        id: popup
        anchor.item: root
        anchor.rect.x: 0
        anchor.rect.y: root.height + 6
        grabFocus: true
        color: "transparent"
        implicitWidth: 360
        implicitHeight: popupLoader.item ? popupLoader.item.contentHeight + 28 : 200
        visible: false

        // Content exists only while the popup is open, so a closed popup
        // costs nothing.
        Loader {
            id: popupLoader
            anchors.fill: parent
            active: popup.visible
            sourceComponent: Component {
                Surface {
                    readonly property real contentHeight: body.implicitHeight
                    anchors.fill: parent
                    borderColor: Theme.popupBorder
                    Item {
                        anchors.fill: parent
                        focus: true
                        Keys.onEscapePressed: popup.visible = false
                    }
                    ColumnLayout {
                        id: body
                        x: 14; y: 14
                        width: parent.width - 28
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            Icon { icon: Theme.iCube; size: 16 }
                            Label { text: "System Updates"; font.pixelSize: Theme.fsBig; font.bold: true; Layout.fillWidth: true }
                            Chip {
                                text: root.state === "updates" ? root.count + " available" : root.stateText()
                                tone: root.state === "updates" ? "info" : root.state === "error" ? "error" : root.state === "reboot" ? "warn" : root.state === "up-to-date" ? "ok" : "muted"
                            }
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                        Section {
                            title: "NixOS"
                            lines: {
                                const s = root.st.system || {};
                                const l = ["Generation " + (s.generation ?? "?") + " · " + Theme.ago(s.generationDate)];
                                if (s.rebootRecommended) l.push("⚠ " + s.rebootReason);
                                return l;
                            }
                        }
                        Section {
                            visible: !!(root.st.nixpkgs && (root.st.nixpkgs.current || root.st.nixpkgs.error))
                            title: "nixpkgs"
                            tone: root.st.nixpkgs && root.st.nixpkgs.updateAvailable ? "info" : ""
                            lines: {
                                const n = root.st.nixpkgs || {};
                                if (n.error) return ["Check failed: " + n.error];
                                if (!n.latest) return ["Not checked yet"];
                                return n.updateAvailable ? ["Update available", (n.currentRev || "") + " → " + (n.latestRev || "")] : ["Up to date (" + (n.currentRev || "") + ")"];
                            }
                        }
                        Section {
                            visible: (root.st.flakeInputs || []).length > 0
                            title: "Flake inputs"
                            lines: {
                                const a = root.st.flakeInputs || [];
                                const out = a.filter(i => i.outdated).length;
                                const pinned = a.filter(i => i.newerUpstream && !i.updatableByLock && i.name !== "nixpkgs").length;
                                const l = [out > 0 ? out + " outdated" : a.length + " inputs, none outdated"];
                                if (pinned > 0) l.push(pinned + " pinned input(s) have newer upstream versions");
                                return l;
                            }
                        }
                        Section {
                            visible: !!(root.st.kernel && !root.st.kernel.hidden && root.st.kernel.running)
                            title: "Kernel"
                            tone: root.st.kernel && root.st.kernel.rebootRequired ? "warn" : ""
                            lines: {
                                const k = root.st.kernel || {};
                                const l = ["Running: " + k.running];
                                if (k.configured && k.configured !== k.running) l.push("Configured: " + k.configured + " (reboot to use)");
                                if (k.updateChangesKernel) l.push("Available after update: " + k.availableAfterUpdate);
                                return l;
                            }
                        }
                        Section {
                            visible: !!(root.st.flatpak && root.st.flatpak.available)
                            title: "Flatpak"
                            tone: root.fpCount() > 0 ? "info" : ""
                            lines: [root.fpCount() > 0 ? root.fpCount() + (root.fpCount() === 1 ? " update" : " updates") : "Up to date"]
                        }
                        Section {
                            visible: !!(root.st.ambxst && root.st.ambxst.available)
                            title: "Ambxst"
                            tone: root.st.ambxst && root.st.ambxst.updateAvailable ? "info" : ""
                            lines: {
                                const a = root.st.ambxst || {};
                                return a.updateAvailable ? [a.version + " → " + a.latestTag + " available (pinned in NixOS config)"]
                                                         : [(a.version || "?") + (a.latestTag ? " · up to date" : "")];
                            }
                        }
                        Section {
                            visible: !!(root.st.mods && root.st.mods.available)
                            title: "Ambxst mods"
                            lines: {
                                const m = root.st.mods || {};
                                const n = (m.mods || []).length;
                                if (n === 0) return ["No mods installed"];
                                return [n + " installed" + (m.updateCount > 0 ? " · " + m.updateCount + " update(s)" : "")];
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                        Label {
                            text: UpdaterState.checkError !== "" ? UpdaterState.checkError
                                : "Last checked " + Theme.ago(root.st.checkedAt)
                            color: UpdaterState.checkError !== "" ? Theme.error : Theme.fgDim
                            font.pixelSize: Theme.fsSmall
                            Layout.fillWidth: true
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Btn {
                                icon: Theme.iSync; text: "Refresh"
                                busy: UpdaterState.checking
                                enabled: !UpdaterState.running
                                onClicked: UpdaterState.check()
                            }
                            Item { Layout.fillWidth: true }
                            Btn {
                                icon: Theme.iLaunch; text: "Open Updater"; kind: "primary"
                                onClicked: { popup.visible = false; UpdaterState.openApp(); }
                            }
                        }
                    }
                }
            }
        }
    }

    function fpCount() {
        const f = st.flatpak || {};
        return ((f.user || {}).updates || []).length + ((f.system || {}).updates || []).length;
    }

    component Section: ColumnLayout {
        property string title: ""
        property var lines: []
        property string tone: ""
        Layout.fillWidth: true
        spacing: 2
        Label {
            text: parent.title
            font.bold: true
            color: parent.tone === "info" ? Theme.tertiary : parent.tone === "warn" ? Theme.warning : Theme.primary
        }
        Repeater {
            model: parent.lines
            Label { required property string modelData; text: modelData; color: Theme.fgDim; Layout.fillWidth: true; elide: Text.ElideRight }
        }
    }
}
