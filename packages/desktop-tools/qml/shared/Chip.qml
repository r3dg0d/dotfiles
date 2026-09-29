import QtQuick

// Small status tag. tone: "ok" | "warn" | "error" | "info" | "muted"
Rectangle {
    id: root
    property string text: ""
    property string tone: "muted"
    readonly property color tc: tone === "ok" ? Theme.ok : tone === "warn" ? Theme.warning
                              : tone === "error" ? Theme.error : tone === "info" ? Theme.tertiary : Theme.outline
    implicitHeight: 20
    implicitWidth: lbl.implicitWidth + 14
    radius: Theme.radius(0)
    color: Qt.rgba(tc.r, tc.g, tc.b, 0.12)
    border.width: 1
    border.color: Qt.rgba(tc.r, tc.g, tc.b, 0.55)
    Label { id: lbl; anchors.centerIn: parent; text: root.text; color: root.tc; font.pixelSize: Theme.fsSmall; font.bold: true }
}
