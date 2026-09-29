import QtQuick

// Flat bordered button in Ambxst's style. kind: "normal" | "primary" | "danger"
Item {
    id: root
    property string icon: ""
    property string text: ""
    property string kind: "normal"
    property bool busy: false
    property string tip: ""
    signal clicked()

    implicitHeight: 32
    implicitWidth: row.implicitWidth + 24
    opacity: enabled ? 1 : 0.45

    readonly property color accent: kind === "danger" ? Theme.error : Theme.primary
    Rectangle {
        anchors.fill: parent
        radius: Theme.radius(0)
        color: root.kind === "normal" ? Theme.background
             : root.kind === "primary" ? Theme.primaryContainer : Theme.errorContainer
        border.width: 1
        border.color: ma.containsMouse && root.enabled ? root.accent : Theme.border
        Behavior on border.color { ColorAnimation { duration: Theme.anim / 3 } }
        Rectangle {
            anchors.fill: parent
            color: root.accent
            opacity: ma.pressed ? 0.25 : (ma.containsMouse && root.enabled ? 0.10 : 0)
            radius: parent.radius
        }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Spinner { visible: root.busy; size: 15; color: root.accent; anchors.verticalCenter: parent.verticalCenter }
        Icon { visible: root.icon !== "" && !root.busy; icon: root.icon; size: 15; color: root.accent; anchors.verticalCenter: parent.verticalCenter }
        Label {
            visible: root.text !== ""
            text: root.text
            color: root.kind === "normal" ? Theme.fg : root.accent
            font.bold: root.kind !== "normal"
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.enabled && !root.busy) root.clicked()
    }
}
