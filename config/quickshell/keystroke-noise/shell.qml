import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property bool shown: false
    property bool enabled: false
    property string detail: ""
    IpcHandler {
        target: "noise"
        function showState(state: string, message: string): void {
            root.enabled = state === "on"
            root.detail = message
            root.shown = true
            dismiss.restart()
        }
    }
    Timer { id: dismiss; interval: 2400; onTriggered: root.shown = false }
    PanelWindow {
        visible: root.shown
        anchors { bottom: true }
        margins.bottom: 90
        implicitWidth: 340; implicitHeight: 100
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "galaxy-keystroke-noise"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Rectangle {
            anchors.fill: parent; anchors.margins: 5
            radius: 22; color: "#0f0d1a"
            border.color: root.enabled ? "#b46bff" : "#26223a"
            Row {
                anchors.centerIn: parent; spacing: 16
                Text { font.family: "Cellforge"; text: "󰌌"; color: root.enabled ? "#d4b8ff" : "#9a96b3"; font.pixelSize: 32; anchors.verticalCenter: parent.verticalCenter }
                Column {
                    spacing: 6
                    Text { font.family: "Cellforge"; text: "KEYSTROKE NOISE"; font.pixelSize: 11; font.letterSpacing: 1.4; color: "#9a96b3" }
                    Text { font.family: "Cellforge"; text: root.detail; color: "#f2f0ff"; font.pixelSize: 14 }
                }
                Rectangle {
                    width: 42; height: 24; radius: 12
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.enabled ? "#b46bff" : "#26223a"
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Rectangle {
                        x: root.enabled ? 21 : 3; y: 3; width: 18; height: 18; radius: 9
                        color: "#f2f0ff"
                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    }
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.shown = false }
        }
    }
}
