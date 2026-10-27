import QtQuick
import QtQuick.Controls

Slider {
    id: s
    property bool dim: false
    from: 0; to: 1; stepSize: 0.01
    implicitHeight: 28
    background: Rectangle {
        x: s.leftPadding; y: s.topPadding + s.availableHeight / 2 - height / 2
        width: s.availableWidth; height: 8; radius: 4; color: "#26223a"
        Rectangle {
            width: s.visualPosition * parent.width; height: parent.height; radius: 4
            opacity: s.dim ? 0.35 : 1
            gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#7c4dff" } GradientStop { position: 1; color: "#d4b8ff" } }
        }
    }
    handle: Rectangle {
        x: s.leftPadding + s.visualPosition * (s.availableWidth - width); y: s.topPadding + s.availableHeight / 2 - height / 2
        width: 18; height: 18; radius: 9
        color: s.pressed ? "#d4b8ff" : "#f2f0ff"; border.color: "#b46bff"; border.width: 2
    }
    WheelHandler { onWheel: ev => { s.value = Math.max(0, Math.min(1, s.value + (ev.angleDelta.y > 0 ? 0.05 : -0.05))); s.moved() } }
}
