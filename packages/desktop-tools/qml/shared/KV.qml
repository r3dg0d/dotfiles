import QtQuick
import QtQuick.Layouts

RowLayout {
    property string k: ""
    property string v: ""
    property color vColor: Theme.fg
    property bool mono: false
    Layout.fillWidth: true
    spacing: 12
    Label { text: parent.k; color: Theme.fgDim; Layout.preferredWidth: 150 }
    Label {
        text: parent.v; color: parent.vColor; Layout.fillWidth: true
        font.family: parent.mono ? Theme.mono : Theme.font
        horizontalAlignment: Text.AlignLeft
    }
}
