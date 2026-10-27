import QtQuick

// Same card language as deepfake/GalaxyPanel.qml: translucent solid fill over the Nebula + lit top hairline.
Rectangle {
    id: card
    default property alias content: inner.data
    property real pad: 14
    implicitHeight: inner.childrenRect.height + pad * 2
    radius: 16
    color: "#d9130e28"
    border.color: "#2e2650"
    Rectangle { x: card.radius; width: parent.width - 2 * card.radius; height: 1; color: "#6a52b0"; opacity: 0.45 }
    Item { id: inner; anchors.fill: parent; anchors.margins: parent.pad }
}
