import QtQuick
import QtQuick.Layouts

// Status pill (same as deepfake/GalaxyPill.qml): state_ = "ok" | "warn" | "err" | "busy" | "idle".
Rectangle {
    id: pill
    property string state_: "idle"
    property string text: ""
    readonly property color fg: state_ === "ok" ? "#7dffa8" : state_ === "warn" ? "#ffd479" : state_ === "err" ? "#ff7a9a" : state_ === "busy" ? "#b46bff" : "#5d5878"
    implicitWidth: row.implicitWidth + 18
    implicitHeight: 24
    radius: 12
    color: state_ === "ok" ? "#1d3a2a" : state_ === "warn" ? "#3a2d12" : state_ === "err" ? "#3a1424" : "#1a1630"
    border.color: state_ === "idle" ? "#3a2f5c" : fg
    Behavior on color { ColorAnimation { duration: 200 } }
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Rectangle {
            width: 7; height: 7; radius: 3.5; color: pill.fg
            SequentialAnimation on opacity {
                running: pill.state_ === "ok" || pill.state_ === "busy"; loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 900 } NumberAnimation { to: 1; duration: 900 }
            }
        }
        Text { font.family: "Cellforge"; font.pixelSize: 10; font.letterSpacing: 1; color: "#f2f0ff"; text: pill.text }
    }
}
