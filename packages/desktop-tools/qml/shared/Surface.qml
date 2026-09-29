import QtQuick

// Bordered halftone panel, the building block of Ambxst's bar pills/popups.
Item {
    id: root
    property color borderColor: Theme.border
    property bool halftone: true
    property color fill: Theme.background
    property int radius: Theme.radius(0)
    default property alias content: inner.data

    Rectangle {
        anchors.fill: parent
        color: root.fill
        radius: root.radius
        clip: true
        Halftone { anchors.fill: parent; visible: root.halftone; base: root.fill }
    }
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: root.radius
        border.width: 1
        border.color: root.borderColor
    }
    Item { id: inner; anchors.fill: parent }
}
