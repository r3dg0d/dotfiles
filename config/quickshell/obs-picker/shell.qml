import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// One-shot screencast target picker for xdg-desktop-portal-wlr (dmenu mode).
// The wrapper (./chooser) feeds xdpw's labels via $OBS_PICKER_ITEMS (JSON
// array of exact lines like "Monitor: DP-1 ..." / "Window: title (id)").
// On selection we write the EXACT label line to $OBS_PICKER_RESULT and quit;
// the wrapper then prints it to stdout for xdpw. Esc writes nothing.
ShellRoot {
    id: root
    property var labels: []
    property int selected: 0
    property string itemsPath: Quickshell.env("OBS_PICKER_ITEMS") || ""
    property string resultPath: Quickshell.env("OBS_PICKER_RESULT") || ""
    property string testMode: Quickshell.env("OBS_PICKER_TEST") || ""

    function friendly(label) {
        if (label.startsWith("Monitor: ")) return "🖥  " + label.slice(9)
        if (label.startsWith("Window: ")) return "🪟  " + label.slice(8)
        return label
    }
    function choose(i) {
        if (i < 0 || i >= labels.length) return
        writer.command = ["/bin/sh", "-c", "printf %s \"$1\" > \"$2\"", "obs-picker", labels[i], resultPath]
        writer.running = true
        quitTimer.restart()
    }
    function cancel() { Qt.quit() }

    FileView {
        path: root.itemsPath
        onLoaded: {
            try { root.labels = JSON.parse(text()) } catch (e) { root.labels = [] }
            if (root.testMode === "first" && root.labels.length > 0) testTimer1.restart()
            else if (root.testMode === "cancel") testTimer2.restart()
        }
    }
    Timer { id: testTimer1; interval: 400; onTriggered: root.choose(0) }
    Timer { id: testTimer2; interval: 400; onTriggered: root.cancel() }
    Timer { id: quitTimer; interval: 300; onTriggered: Qt.quit() }
    Process { id: writer }

    PanelWindow {
        visible: true
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "obs-picker"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: "#b307060d"
            focus: true
            Component.onCompleted: forceActiveFocus()
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Escape) root.cancel()
                else if (event.key === Qt.Key_Down) root.selected = Math.min(root.labels.length - 1, root.selected + 1)
                else if (event.key === Qt.Key_Up) root.selected = Math.max(0, root.selected - 1)
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.choose(root.selected)
                else return
                event.accepted = true
            }
            MouseArea { anchors.fill: parent; onClicked: root.cancel() }

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: Math.min(760, parent.width - 80)
                implicitHeight: Math.min(560, 120 + root.labels.length * 58)
                height: implicitHeight
                radius: 22
                color: "#0f0d1a"
                border.width: 1; border.color: "#b46bff"
                MouseArea { anchors.fill: parent } // swallow clicks (no cancel inside)
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 22; spacing: 12
                    Text { font.family: "Cellforge"; text: "✦  S H A R E   A   S C R E E N"; color: "#d4b8ff"; font.pixelSize: 13 }
                    Text { font.family: "Cellforge"; text: "Pick a display to capture — Enter/click to share, Esc to cancel"; color: "#9a96b3"; font.pixelSize: 13 }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 8
                        Repeater {
                            model: root.labels
                            Rectangle {
                                required property int index
                                required property string modelData
                                Layout.fillWidth: true; height: 50; radius: 14
                                color: index === root.selected ? "#1a1630" : "#0b0914"
                                border.width: 1; border.color: index === root.selected ? "#b46bff" : "#26223a"
                                Text { font.family: "Cellforge";
                                    anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 16
                                    anchors.right: parent.right; anchors.rightMargin: 16
                                    text: root.friendly(modelData); elide: Text.ElideRight
                                    color: "#f2f0ff"; font.pixelSize: 15
                                }
                                MouseArea {
                                    anchors.fill: parent; hoverEnabled: true
                                    onEntered: root.selected = index
                                    onClicked: root.choose(index)
                                }
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Text { font.family: "Cellforge"; text: root.labels.length + " source(s) · ↑ ↓ Enter · Esc"; color: "#5d5878"; font.pixelSize: 12 }
                }
            }
        }
    }
}
