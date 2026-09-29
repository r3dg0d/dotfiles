import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.shared

// Bar pill: free space at a glance; click for a compact storage popup.
// "Safe Clean" here never deletes anything: it opens Storage Optimizer on
// its review/confirmation page.
Item {
    id: root
    property alias popupOpen: popup.visible
    signal requestExclusive()

    readonly property var h: StorageState.home
    readonly property var last: StorageState.lastScan
    readonly property real pct: h.percent || 0
    readonly property string display: (StorageState.summary.widget || {}).display || "free"
    readonly property color accent: pct >= 95 ? Theme.error : pct >= 85 ? Theme.warning : Theme.primary
    // Busy in this process or in the app (via the helper's activity file).
    readonly property bool busy: StorageState.busyKind !== ""

    implicitHeight: 36
    implicitWidth: pillRow.implicitWidth + 24

    Surface {
        anchors.fill: parent
        borderColor: ma.containsMouse || popup.visible ? root.accent : Theme.border
        Rectangle { anchors.fill: parent; color: root.accent; opacity: ma.pressed ? 0.2 : (ma.containsMouse ? 0.08 : 0) }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 8
            Spinner { visible: root.busy; size: 16; anchors.verticalCenter: parent.verticalCenter }
            Icon { visible: !root.busy; icon: Theme.iHdd; color: root.accent; anchors.verticalCenter: parent.verticalCenter }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                font.bold: true
                color: root.busy ? Theme.primary : root.pct >= 85 ? root.accent : Theme.fg
                text: root.busy ? (StorageState.busyKind === "cleaning" ? "Cleaning…" : "Analyzing…")
                    : !root.h.size ? "—"
                    : root.display === "percent" ? Math.round(root.pct) + "%"
                    : Theme.bytes(root.h.avail) + " free"
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
            if (m.button === Qt.MiddleButton) { StorageState.openApp(); return; }
            if (!popup.visible) { root.requestExclusive(); StorageState.refreshSummary(); }
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
        implicitWidth: 490
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
                    Item { anchors.fill: parent; focus: true; Keys.onEscapePressed: popup.visible = false }
                    ColumnLayout {
                        id: body
                        x: 14; y: 14
                        width: parent.width - 28
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            Icon { icon: Theme.iHdd; size: 16 }
                            Label { text: "Storage"; font.pixelSize: Theme.fsBig; font.bold: true; Layout.fillWidth: true }
                            Chip { text: Math.round(root.pct) + "% used"; tone: root.pct >= 95 ? "error" : root.pct >= 85 ? "warn" : "ok"; visible: !!root.h.size }
                        }
                        Bar { Layout.fillWidth: true; value: root.pct / 100; barColor: root.accent }
                        GridLayout {
                            columns: 2; columnSpacing: 12; rowSpacing: 4
                            Layout.fillWidth: true
                            Label { text: "Used"; color: Theme.fgDim }
                            Label { text: Theme.bytes(root.h.used) + " of " + Theme.bytes(root.h.size); Layout.fillWidth: true }
                            Label { text: "Free"; color: Theme.fgDim }
                            Label { text: Theme.bytes(root.h.avail) }
                            Label { text: "Safe cleanup"; color: Theme.fgDim }
                            Label {
                                text: root.last ? Theme.bytes(root.last.safeCleanDefault) + " selected by default · " + Theme.bytes(root.last.safeCleanEstimate) + " max"
                                                : "Analyze to estimate"
                                color: root.last ? Theme.primary : Theme.fgDim
                                Layout.fillWidth: true
                            }
                            Label { text: "Largest"; color: Theme.fgDim }
                            Label {
                                text: root.last && root.last.largest ? root.last.largest.label + " — " + Theme.bytes(root.last.largest.bytes) : "—"
                                Layout.fillWidth: true
                            }
                        }
                        Indeterminate {
                            visible: root.busy
                            Layout.fillWidth: true
                            barColor: StorageState.busyKind === "cleaning" ? Theme.primary : Theme.tertiary
                        }
                        Label {
                            visible: root.busy && !StorageState.scanning
                            text: StorageState.busyPhase
                            color: Theme.primary
                            Layout.fillWidth: true
                        }
                        Label {
                            Layout.fillWidth: true
                            font.pixelSize: Theme.fsSmall
                            color: StorageState.scanning ? Theme.tertiary : Theme.fgDim
                            text: StorageState.scanning
                                ? "Analyzing… " + Theme.bytes(StorageState.progress.bytes || 0) + " in " + (StorageState.progress.files || 0).toLocaleString() + " files"
                                : root.last ? "Last analyzed " + Theme.ago(root.last.finishedAt) : "Not analyzed yet — no background scanning"
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Btn {
                                icon: StorageState.scanning ? Theme.iX : Theme.iSync
                                text: StorageState.scanning ? "Cancel" : "Analyze"
                                enabled: StorageState.scanning || !root.busy
                                onClicked: StorageState.scanning ? StorageState.cancelScan() : StorageState.startScan()
                            }
                            Btn {
                                icon: Theme.iBroom; text: "Safe Clean…"
                                enabled: !root.busy
                                onClicked: { popup.visible = false; StorageState.openApp("clean"); }
                            }
                            Item { Layout.fillWidth: true }
                            Btn {
                                icon: Theme.iLaunch; text: "Open Storage Optimizer"; kind: "primary"
                                onClicked: { popup.visible = false; StorageState.openApp(); }
                            }
                        }
                    }
                }
            }
        }
    }
}
