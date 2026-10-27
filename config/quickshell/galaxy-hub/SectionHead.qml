import QtQuick
import QtQuick.Layouts

RowLayout {
    property string label: ""
    property string icon: ""
    property string badge: ""
    Layout.fillWidth: true; Layout.topMargin: 4; spacing: 8
    Text { text: parent.icon; color: "#b46bff"; font.pixelSize: 14 }
    Text { Layout.fillWidth: true; text: parent.label; color: "#d4b8ff"; font.family: "Cellforge"; font.pixelSize: 11; font.letterSpacing: 1.2 }
    Rectangle {
        visible: parent.badge.length > 0
        implicitWidth: badgeText.implicitWidth + 14; implicitHeight: 18; radius: 9
        gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#b46bff" } GradientStop { position: 1; color: "#7c4dff" } }
        Text { id: badgeText; anchors.centerIn: parent; text: parent.parent.badge; color: "#07060d"; font.family: "Cellforge"; font.pixelSize: 10 }
    }
}
