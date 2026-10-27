import QtQuick
import QtQuick.Layouts

Rectangle {
    id: row
    property var node
    property bool current: false
    property bool mic: false
    signal picked()
    Layout.fillWidth: true; height: 32; radius: 10
    color: mouse.containsMouse ? "#1a1630" : "#0b0914"
    border.color: current ? "#b46bff" : "#26223a"
    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
        Text { text: row.mic ? "󰍬" : ((row.node && row.node.name || "").indexOf("Headphones") >= 0 ? "󰋋" : (row.node && row.node.name || "").indexOf("SPDIF") >= 0 ? "󰓃" : "󰓃"); color: row.current ? "#d4b8ff" : "#5d5878"; font.pixelSize: 14 }
        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: row.node ? (row.node.description || row.node.nickname || row.node.name) : ""; color: row.current ? "#f2f0ff" : "#9a96b3"; font.family: "Cellforge"; font.pixelSize: 12 }
        Text { visible: row.current; text: "󰄬"; color: "#7dffa8"; font.pixelSize: 13 }
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: row.picked() }
}
