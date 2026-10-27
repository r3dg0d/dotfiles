import QtQuick
import QtQuick.Effects

// Album art with rounded corners (MultiEffect mask), a violet glow that breathes while playing,
// and a ✦ placeholder on a tiny nebula when there's no art.
Item {
    id: art
    property url source: ""
    property bool playing: false
    property real radius: 18
    property bool compact: false
    readonly property bool hasArt: img.status === Image.Ready && String(source).length > 0

    // glow: blurred copy of the art (or a violet tile) behind it
    Rectangle { id: glowSrc; anchors.fill: parent; radius: art.radius; color: "#7c4dff"; visible: false; layer.enabled: true }
    MultiEffect {
        anchors.fill: parent
        source: art.hasArt ? clipped : glowSrc
        blurEnabled: true; blurMax: art.compact ? 16 : 48; blur: 1.0
        brightness: 0.05; saturation: 0.3
        autoPaddingEnabled: true
        opacity: art.playing ? glowPulse.v : 0.32
        QtObject { id: glowPulse; property real v: 0.55
            SequentialAnimation on v { running: art.playing && art.visible; loops: Animation.Infinite
                NumberAnimation { to: 0.75; duration: 1800; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.45; duration: 1800; easing.type: Easing.InOutSine } } }
    }
    Rectangle { anchors.fill: parent; radius: art.radius; color: "#0e0a1c"; border.color: "#3a2f5c" }
    Nebula { anchors.fill: parent; radius: art.radius; seed: 41; stars: 2.5; glow: 1.6; rim: false; visible: !art.hasArt }
    Text { anchors.centerIn: parent; visible: !art.hasArt; text: "✦"; color: "#b46bff"; font.family: "Cellforge"; font.pixelSize: art.height * 0.3 }

    Image { id: img; anchors.fill: parent; source: art.source; fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: false; smooth: true; mipmap: true }
    Rectangle { id: mask; anchors.fill: parent; radius: art.radius; visible: false; layer.enabled: true; layer.smooth: true }
    MultiEffect {
        id: clipped
        anchors.fill: parent; visible: art.hasArt
        source: img; maskEnabled: true; maskSource: mask
        maskThresholdMin: 0.5; maskSpreadAtMin: 1.0
    }
    // thin luminous rim on top
    Rectangle { anchors.fill: parent; radius: art.radius; color: "transparent"; border.width: 1; border.color: art.playing ? "#8a6bd8" : "#3a2f5c"
        Behavior on border.color { ColorAnimation { duration: 260 } } }
}
