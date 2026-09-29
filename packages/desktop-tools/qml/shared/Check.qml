import QtQuick

Item {
    id: root
    property bool checked: false
    property string text: ""
    signal toggled(bool value)
    implicitHeight: 22
    implicitWidth: 22 + (text ? lbl.implicitWidth + 8 : 0)
    opacity: enabled ? 1 : 0.4
    Rectangle {
        id: box
        width: 18; height: 18
        anchors.verticalCenter: parent.verticalCenter
        color: root.checked ? Theme.primary : Theme.background
        border.width: 1
        border.color: root.checked ? Theme.primary : Theme.outline
        radius: Theme.radius(-2)
        Icon { anchors.centerIn: parent; icon: Theme.iCheck; size: 12; color: Theme.onPrimary; visible: root.checked }
    }
    Label { id: lbl; visible: root.text !== ""; text: root.text; x: 26; anchors.verticalCenter: parent.verticalCenter }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.enabled) { root.checked = !root.checked; root.toggled(root.checked); }
    }
}
