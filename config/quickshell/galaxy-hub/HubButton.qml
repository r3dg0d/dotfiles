import QtQuick
import QtQuick.Controls

// deep-space button shared look (Cellforge labels, Nerd Font glyph fallback)
Button {
    id: control
    property bool primary: false
    property bool danger: false
    property bool selected: false
    property string hint: ""
    ToolTip.visible: hovered && hint.length > 0
    ToolTip.text: hint
    ToolTip.delay: 400
    implicitWidth: Math.max(36, label.implicitWidth + 26)
    implicitHeight: 32
    hoverEnabled: true
    padding: 6
    font.family: "Cellforge"
    font.pixelSize: 13
    contentItem: Text {
        id: label
        text: control.text
        font: control.font
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: !control.enabled ? "#5d5878" : control.primary ? "#07060d" : control.danger ? "#ff5c8a" : "#d4b8ff"
    }
    background: Rectangle {
        radius: 10
        color: !control.enabled ? "#0b0914"
             : control.down ? "#7c4dff"
             : control.primary ? (control.hovered ? "#d4b8ff" : "#b46bff")
             : (control.hovered || control.selected) ? "#1a1630" : "#0f0d1a"
        border.width: 1
        border.color: control.danger && control.hovered ? "#ff5c8a" : (control.hovered || control.selected) ? "#b46bff" : "#26223a"
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }
}
