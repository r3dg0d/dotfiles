import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import qs.shared

// Session polkit authentication agent with a password prompt styled like the
// shell. It lives in the always-running widget shell, draws on the overlay
// layer (it can't end up behind a window) and takes the keyboard while shown.
// It answers every polkit request in the session — NixOS Updater, Storage
// Optimizer, Flatpak, pkexec, … The password goes straight to polkit's PAM
// helper via AuthFlow.submit(); it is never stored or logged here.
Scope {
    id: root

    PolkitAgent { id: agent }

    readonly property var flow: agent.flow
    readonly property bool shown: agent.isActive && flow !== null
    property bool verifying: false

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onIsResponseRequiredChanged() {
            if (root.flow && root.flow.isResponseRequired) {
                root.verifying = false;
                pw.text = "";
                pw.forceActiveFocus();
            }
        }
        function onAuthenticationFailed() { root.verifying = false; pw.text = ""; shake.restart(); }
        function onIsCompletedChanged() { root.verifying = false; pw.text = ""; }
    }
    onShownChanged: {
        pw.text = "";
        verifying = false;
        if (shown) Qt.callLater(() => pw.forceActiveFocus());
    }

    function submit() {
        if (!flow || !flow.isResponseRequired || verifying) return;
        verifying = true;
        flow.submit(pw.text);
        pw.text = "";
    }
    function cancel() {
        if (flow) flow.cancelAuthenticationRequest();
        pw.text = "";
        verifying = false;
    }

    PanelWindow {
        id: win
        visible: root.shown
        screen: Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "zionsec-polkit"
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: root.shown ? 0.55 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.anim / 2 } }
        }
        // Clicks outside the dialog do nothing: the request needs an explicit answer.
        MouseArea { anchors.fill: parent }

        Surface {
            id: dialog
            width: 480
            height: col.implicitHeight + 36
            anchors.centerIn: parent
            borderColor: root.flow && root.flow.failed ? Theme.error : Theme.popupBorder

            SequentialAnimation {
                id: shake
                NumberAnimation { target: dialog; property: "anchors.horizontalCenterOffset"; to: -10; duration: 50 }
                NumberAnimation { target: dialog; property: "anchors.horizontalCenterOffset"; to: 10; duration: 70 }
                NumberAnimation { target: dialog; property: "anchors.horizontalCenterOffset"; to: -6; duration: 60 }
                NumberAnimation { target: dialog; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
            }

            ColumnLayout {
                id: col
                x: 18; y: 18
                width: parent.width - 36
                spacing: 10

                RowLayout {
                    spacing: 10
                    Icon { icon: Theme.iShield; size: 22 }
                    Label { text: "Authentication required"; font.pixelSize: Theme.fsBig + 2; font.bold: true; Layout.fillWidth: true }
                }
                Label {
                    text: root.flow ? root.flow.message : ""
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Label {
                    readonly property var ident: root.flow ? root.flow.selectedIdentity : null
                    visible: text !== ""
                    text: ident && ident.displayName ? "Authenticating as " + ident.displayName : ""
                    color: Theme.fgDim
                    Layout.fillWidth: true
                }
                Label {
                    text: root.flow ? root.flow.actionId : ""
                    color: Theme.fgDim
                    font.family: Theme.mono
                    font.pixelSize: Theme.fsSmall
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                }

                Label {
                    text: root.flow && root.flow.inputPrompt ? root.flow.inputPrompt.replace(/:\s*$/, "") : "Password"
                    color: Theme.fgDim
                }
                TextField {
                    id: pw
                    Layout.fillWidth: true
                    implicitHeight: 34
                    echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    enabled: !!(root.flow && root.flow.isResponseRequired) && !root.verifying
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fs
                    selectByMouse: true
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    background: Rectangle {
                        color: Theme.surfaceDim
                        border.width: 1
                        border.color: pw.activeFocus ? Theme.primary : Theme.border
                        radius: Theme.radius(0)
                    }
                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                    Keys.onEscapePressed: root.cancel()
                }

                Indeterminate { visible: root.verifying; Layout.fillWidth: true }
                Label {
                    visible: text !== ""
                    text: root.verifying ? "Verifying…"
                        : root.flow && root.flow.supplementaryMessage ? root.flow.supplementaryMessage
                        : root.flow && root.flow.failed ? "Authentication failed. Try again." : ""
                    color: root.verifying ? Theme.fgDim : (root.flow && (root.flow.supplementaryIsError || root.flow.failed)) ? Theme.error : Theme.fgDim
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Item { Layout.fillWidth: true }
                    Btn { text: "Cancel"; icon: Theme.iX; onClicked: root.cancel() }
                    Btn {
                        text: "Authenticate"; icon: Theme.iCheck; kind: "primary"
                        busy: root.verifying
                        enabled: !!(root.flow && root.flow.isResponseRequired)
                        onClicked: root.submit()
                    }
                }
            }
        }
    }
}
