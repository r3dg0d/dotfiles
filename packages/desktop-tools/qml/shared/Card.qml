import QtQuick
import QtQuick.Layouts

// Titled panel used by both apps.
Surface {
    id: root
    property string icon: ""
    property string title: ""
    property string chip: ""
    property string chipTone: "muted"
    default property alias body: col.data
    implicitHeight: col.implicitHeight + head.height + 30
    halftone: false
    fill: Theme.background

    RowLayout {
        id: head
        x: 14; y: 12
        width: parent.width - 28
        height: 22
        spacing: 8
        Icon { icon: root.icon; size: 16; visible: root.icon !== "" }
        Label { text: root.title; font.pixelSize: Theme.fsBig; font.bold: true; Layout.fillWidth: true }
        Chip { text: root.chip; tone: root.chipTone; visible: root.chip !== "" }
    }
    ColumnLayout {
        id: col
        x: 14
        y: head.y + head.height + 10
        width: parent.width - 28
        spacing: 6
    }
}
