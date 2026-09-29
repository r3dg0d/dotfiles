import QtQuick

// Thin horizontal meter.
Rectangle {
    property real value: 0   // 0..1
    property color barColor: Theme.primary
    implicitHeight: 6
    color: Theme.surfaceContainer
    radius: Theme.radius(0)
    Rectangle {
        width: Math.max(0, Math.min(1, parent.value)) * parent.width
        height: parent.height
        color: parent.barColor
        radius: parent.radius
        Behavior on width { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
    }
}
