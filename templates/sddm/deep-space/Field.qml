import QtQuick

Rectangle {
    id: f
    property alias text: input.text
    property string placeholder: ""
    property string icon: ""
    property bool secret: false
    signal accepted()
    function forceFocus() { input.forceActiveFocus() }
    function clear() { input.text = "" }

    height: 48; radius: 14
    color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.07 : 0.04)
    border.width: input.activeFocus ? 2 : 1
    border.color: input.activeFocus ? "{{violet}}" : Qt.rgba(1, 1, 1, 0.10)

    Text {
        id: ic
        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
        text: f.icon; color: input.activeFocus ? "{{violet}}" : "{{subtext}}"
        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16
    }
    TextInput {
        id: input
        anchors { left: ic.right; right: parent.right; leftMargin: 12; rightMargin: 16; verticalCenter: parent.verticalCenter }
        color: "{{text}}"; selectionColor: "{{overlay}}"; selectedTextColor: "{{text}}"
        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15
        echoMode: f.secret ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        clip: true
        onAccepted: f.accepted()
        Keys.onEscapePressed: text = ""
    }
    Text {
        anchors.fill: input; verticalAlignment: Text.AlignVCenter
        text: f.placeholder; color: "{{muted}}"
        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15
        visible: input.text.length === 0
    }
    MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus(); cursorShape: Qt.IBeamCursor }
}
