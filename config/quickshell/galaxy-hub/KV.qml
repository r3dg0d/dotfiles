import QtQuick
import QtQuick.Layouts

RowLayout {
    property string k: ""
    property string v: ""
    property bool accent: false
    property bool warn: false
    Layout.fillWidth: true
    Text { Layout.preferredWidth: 96; text: parent.k; color: "#5d5878"; font.family: "Cellforge"; font.pixelSize: 11 }
    Text { Layout.fillWidth: true; text: parent.v; elide: Text.ElideRight; color: parent.warn ? "#ffd479" : parent.accent ? "#b46bff" : "#f2f0ff"; font.family: "NullType"; font.pixelSize: 12 }
}
