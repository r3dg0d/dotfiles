import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property bool shown: false
    property string label: ""
    property string icon: ""
    property real value: -1
    property bool muted: false
    IpcHandler {
        target: "system"
        function showState(label: string, icon: string, value: string, muted: string): void {
            root.label = label; root.icon = icon; root.value = Number(value)
            root.muted = muted === "true"; root.shown = true; dismiss.restart()
        }
    }
    Timer { id: dismiss; interval: 1800; onTriggered: root.shown = false }
    PanelWindow {
        visible: root.shown
        anchors { bottom: true }
        margins.bottom: 90
        implicitWidth: root.label.indexOf("\n") >= 0 ? 460 : 380; implicitHeight: root.label.indexOf("\n") >= 0 ? 136 : 112
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "galaxy-system-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Rectangle {
            anchors.fill: parent; anchors.margins: 5; radius: 24
            color: "#0f0d1a"; border.color: root.muted ? "#5d5878" : "#b46bff"
            Row {
                anchors.centerIn: parent; spacing: 16
                Text { font.family: "Cellforge"; text: root.icon; font.pixelSize: 28; color: root.muted ? "#9a96b3" : "#d4b8ff"; anchors.verticalCenter: parent.verticalCenter }
                Column {
                    width: root.label.indexOf("\n") >= 0 ? 360 : 280; spacing: 12
                    Text { font.family: "Cellforge"; width: parent.width; text: root.label; textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; color: "#f2f0ff"; font.pixelSize: 14 }
                    Rectangle {
                        width: parent.width; height: 7; radius: 4; color: "#26223a"
                        visible: root.value >= 0
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, root.value / 100)); height: parent.height; radius: 4
                            color: root.muted ? "#5d5878" : "#b46bff"
                            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.shown = false }
        }
    }
}
