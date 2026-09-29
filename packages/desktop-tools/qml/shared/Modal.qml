import QtQuick

// In-window modal: dims the app and shows a bordered panel. Clicking the dim
// area does nothing on purpose — every modal needs an explicit choice.
Item {
    id: root
    anchors.fill: parent
    visible: false
    z: 100
    property int panelWidth: 640
    property int panelHeight: 480
    default property alias content: panel.content
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.6 }
    MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: w => w.accepted = true }
    Surface {
        id: panel
        width: Math.min(root.panelWidth, root.width - 40)
        height: Math.min(root.panelHeight, root.height - 40)
        anchors.centerIn: parent
        halftone: false
        borderColor: Theme.popupBorder
    }
}
