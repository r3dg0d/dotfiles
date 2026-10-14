// deep-space SDDM theme (Qt 6). Imports only QtQuick so it runs with the stock sddm-greeter-qt6.
import QtQuick

Rectangle {
    id: root
    width: 1920; height: 1080
    color: "#07060d"
    readonly property color accent: config.accent || "#b46bff"
    readonly property string fontName: config.font || "JetBrainsMono Nerd Font"
    property int sessionIdx: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property string sessionName: ""

    Image {
        anchors.fill: parent
        source: config.background || "background.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    // A few dozen slowly twinkling stars on top of the static wallpaper.
    Repeater {
        model: 48
        Rectangle {
            readonly property real seed: (index * 9301 + 49297) % 233280 / 233280
            x: ((index * 7919) % 997) / 997 * root.width
            y: ((index * 6151) % 991) / 991 * root.height
            width: 1.5 + seed * 2.5; height: width; radius: width / 2
            color: index % 5 === 0 ? "#d4b8ff" : "#f2f0ff"
            opacity: 0.2
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                PauseAnimation { duration: 400 + seed * 4000 }
                NumberAnimation { to: 0.95; duration: 1800 + seed * 1500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.15; duration: 2200 + seed * 1500; easing.type: Easing.InOutSine }
            }
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.12
        spacing: 2
        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: root.fontName; font.pixelSize: Math.round(root.height * 0.09); font.weight: Font.Light
            color: "#f2f0ff"
            text: Qt.formatTime(new Date(), "HH:mm")
        }
        Text {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: root.fontName; font.pixelSize: Math.round(root.height * 0.022)
            color: "#d4b8ff"
            text: Qt.formatDate(new Date(), "dddd, d MMMM")
        }
        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: { clock.text = Qt.formatTime(new Date(), "HH:mm"); date.text = Qt.formatDate(new Date(), "dddd, d MMMM") }
        }
    }

    // Glass login card
    Rectangle {
        id: card
        width: Math.min(440, root.width * 0.86); height: col.implicitHeight + 56
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.height * 0.08
        radius: 22
        color: Qt.rgba(0.06, 0.05, 0.10, 0.62)
        border.color: Qt.rgba(1, 1, 1, 0.10); border.width: 1
        Rectangle {  // violet sheen along the top edge
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
            height: parent.height * 0.5; radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.71, 0.42, 1.0, 0.16) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 28 }
            spacing: 14

            Text {
                text: "welcome back"
                color: "#9a96b3"; font.family: root.fontName; font.pixelSize: 14; font.letterSpacing: 2
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Field {
                id: userField
                width: parent.width
                placeholder: "user"
                icon: ""
                text: userModel.lastUser
                onAccepted: passField.forceFocus()
            }
            Field {
                id: passField
                width: parent.width
                placeholder: "password"
                icon: ""
                secret: true
                onAccepted: root.doLogin()
            }

            Rectangle {
                id: loginBtn
                width: parent.width; height: 46; radius: 14
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#7c4dff" }
                    GradientStop { position: 1.0; color: root.accent }
                }
                opacity: loginArea.pressed ? 0.8 : 1
                Text { anchors.centerIn: parent; text: "log in  →"; color: "#07060d"; font.family: root.fontName; font.pixelSize: 15; font.bold: true }
                MouseArea { id: loginArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.doLogin() }
            }

            Text {
                id: message
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                color: "#ff5c8a"; font.family: root.fontName; font.pixelSize: 13
                text: ""
            }
        }
    }

    // Bottom bar: session picker + power
    Row {
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 28 }
        spacing: 12
        Pill {
            label: "  " + (root.sessionName || "session")
            onClicked: root.sessionIdx = (root.sessionIdx + 1) % Math.max(1, sessionModel.count)
        }
        Pill { label: "  reboot"; visible: sddm.canReboot; onClicked: sddm.reboot() }
        Pill { label: "  power off"; visible: sddm.canPowerOff; onClicked: sddm.powerOff() }
    }

    // Resolve the session name for the current index.
    Repeater {
        model: sessionModel
        Item { visible: false
            Component.onCompleted: if (index === root.sessionIdx) root.sessionName = model.name
            Connections { target: root; function onSessionIdxChanged() { if (index === root.sessionIdx) root.sessionName = model.name } }
        }
    }

    function doLogin() {
        message.text = ""
        sddm.login(userField.text, passField.text, root.sessionIdx)
    }
    Connections {
        target: sddm
        function onLoginFailed() { message.text = "login failed — try again"; passField.clear(); passField.forceFocus() }
        function onLoginSucceeded() { message.color = "#7dffa8"; message.text = "welcome" }
    }

    Component.onCompleted: {
        if (userField.text.length > 0) passField.forceFocus(); else userField.forceFocus()
    }
}
