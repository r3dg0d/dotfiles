import QtQuick
import QtQuick.Controls

// Append-only log with follow-tail, used for rebuild/cleanup output.
Rectangle {
    id: root
    property alias text: area.text
    color: Theme.background
    border.width: 1
    border.color: Qt.rgba(Theme.luminous.r, Theme.luminous.g, Theme.luminous.b, 0.35)
    radius: Theme.radius(0)
    function append(line) {
        area.append(line);
        if (follow) area.cursorPosition = area.length;
    }
    function clear() { area.clear(); }
    property bool follow: true
    ScrollView {
        id: sv
        anchors.fill: parent
        anchors.margins: 6
        TextArea {
            id: area
            readOnly: true
            wrapMode: TextEdit.WrapAnywhere
            color: Theme.fgDim
            font.family: Theme.mono
            font.pixelSize: 12
            selectByMouse: true
            background: null
        }
    }
}
