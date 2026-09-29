import QtQuick

// Indeterminate progress: a highlight sweeping across a thin track. Animates
// only while visible so hidden instances cost nothing.
Rectangle {
    id: track
    property color barColor: Theme.primary
    implicitHeight: 4
    color: Theme.surfaceContainer
    radius: Theme.radius(0)
    clip: true

    Rectangle {
        id: sweep
        width: Math.max(40, track.width * 0.3)
        height: track.height
        radius: track.radius
        color: track.barColor
        x: -width
    }
    SequentialAnimation {
        running: track.visible && track.width > 0
        loops: Animation.Infinite
        NumberAnimation {
            target: sweep; property: "x"
            from: -sweep.width; to: track.width
            duration: 1100; easing.type: Easing.InOutCubic
        }
        PauseAnimation { duration: 150 }
    }
}
