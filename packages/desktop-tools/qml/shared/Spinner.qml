import QtQuick

// Animates only while actually shown; hidden spinners must not keep the
// scene graph repainting (that alone cost ~7% CPU idle in the bar).
Icon {
    id: sp
    icon: Theme.iSpinner
    RotationAnimation on rotation {
        running: sp.visible
        from: 0; to: 360; duration: 900
        loops: Animation.Infinite
    }
}
