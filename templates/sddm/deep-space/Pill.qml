import QtQuick

Rectangle {
    id: p
    property string label: ""
    signal clicked()
    height: 36; width: t.implicitWidth + 32; radius: 18
    color: Qt.rgba(0.06, 0.05, 0.10, area.containsMouse ? 0.85 : 0.6)
    border.width: 1
    border.color: area.containsMouse ? "{{violet}}" : Qt.rgba(1, 1, 1, 0.10)
    Text { id: t; anchors.centerIn: parent; text: p.label; color: "{{text}}"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: p.clicked() }
}
