import QtQuick
Window {
    property PanelAnchors anchors: PanelAnchors { }
    property int exclusionMode: 0
    property int exclusiveZone: 0
    property int implicitWidth: 0
    property int implicitHeight: 0
    width: implicitWidth > 0 ? implicitWidth : 1600
    height: implicitHeight > 0 ? implicitHeight : 900
}
