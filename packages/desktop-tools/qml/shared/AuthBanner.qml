import QtQuick
import QtQuick.Layouts

// Shown while a privileged step waits for the polkit password prompt, and
// when authentication fails. state: "" | "waiting" | "granted" | "failed"
Surface {
    id: root
    property string state: ""
    property string message: ""
    visible: state === "waiting" || state === "failed"
    implicitHeight: 48
    halftone: false
    borderColor: state === "failed" ? Theme.error : Theme.warning

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12
        Icon {
            icon: root.state === "failed" ? Theme.iAlert : Theme.iShield
            color: root.state === "failed" ? Theme.error : Theme.warning
            size: 20
            SequentialAnimation on opacity {
                running: root.visible && root.state === "waiting"
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
            }
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: root.state === "failed" ? Theme.error : Theme.fg
            text: root.message !== "" ? root.message
                : root.state === "waiting" ? "Authentication required — enter your password in the prompt."
                : "Authentication failed."
        }
    }
}
