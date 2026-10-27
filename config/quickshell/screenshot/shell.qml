import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property bool opened: false
    property string sourcePath: ""
    property string tool: "pen"
    property string ink: "#b46bff"
    property var marks: []
    property var current: null
    property string message: "Choose a tool to annotate, or copy the original."
    property bool editing: false
    IpcHandler {
        target: "editor"
        function openFile(path: string): void {
            root.sourcePath = path; root.marks = []; root.current = null
            root.editing = false; root.message = "Screenshot saved locally · choose an action"
            root.opened = true; drawing.requestPaint()
        }
    }
    function exportImage(action) {
        if (exporter.running || !sourcePath) return
        message = action === "upload" ? "Uploading…" : "Rendering…"
        exporter.command = ["python3", Quickshell.shellPath("export.py"), sourcePath, JSON.stringify(marks), action, endpoint.text]
        exporter.running = true
    }
    Process {
        id: importer
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.message = JSON.parse(text).message }
                catch (e) { root.message = "Uploader import failed" }
            }
        }
    }
    Process {
        id: exporter
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.message = JSON.parse(text).message }
                catch (e) { root.message = "Action failed; screenshot remains saved locally." }
            }
        }
    }
    FloatingWindow {
        id: editorWindow
        title: "Galaxy Screenshot"
        visible: root.opened
        implicitWidth: 1060; implicitHeight: 760
        minimumSize: Qt.size(740, 480)
        color: "transparent"
        onClosed: root.opened = false
        Nebula { anchors.fill: parent; radius: 22; seed: 31; glow: 0.7 }
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 20; spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Text { font.family: "Cellforge";
                    Layout.fillWidth: true; text: "✦  G A L A X Y  /  S C R E E N S H O T"
                    color: "#d4b8ff"; font.pixelSize: 13
                    MouseArea { anchors.fill: parent; cursorShape: Qt.SizeAllCursor; onPressed: editorWindow.startSystemMove() }
                }
                GalaxyButton { text: "×"; Accessible.name: "Close screenshot"; onClicked: root.opened = false }
            }
            RowLayout {
                Layout.fillWidth: true
                GalaxyButton { text: "Edit"; selected: root.editing; onClicked: root.editing = !root.editing }
                GalaxyButton { text: "Host settings"; onClicked: uploadSettings.visible = !uploadSettings.visible }
                Item { Layout.fillWidth: true }
                GalaxyButton { text: "Save"; enabled: !exporter.running; onClicked: root.exportImage("save") }
                GalaxyButton { text: "Copy"; primary: true; enabled: !exporter.running; onClicked: root.exportImage("copy") }
                GalaxyButton { text: "Upload ↗"; enabled: !exporter.running; onClicked: { if (!endpoint.text) { uploadSettings.visible = true; endpoint.forceActiveFocus(); root.message = "Choose an upload endpoint; no image has been sent." } else root.exportImage("upload") } }
            }
            RowLayout {
                visible: root.editing; spacing: 8
                Repeater {
                    model: ["pen", "arrow", "rectangle", "redact"]
                    GalaxyButton {
                        required property string modelData
                        text: modelData; selected: root.tool === modelData
                        onClicked: root.tool = modelData
                    }
                }
                GalaxyButton { text: "Undo"; enabled: root.marks.length > 0; onClicked: { root.marks = root.marks.slice(0,-1); drawing.requestPaint() } }
                Repeater {
                    model: ["#b46bff", "#ff5c8a", "#ffd479", "#f2f0ff"]
                    Rectangle {
                        required property string modelData
                        width: 26; height: 26; radius: 13; color: modelData
                        border.width: root.ink === modelData ? 3 : 0; border.color: "#7dffa8"
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.ink = parent.modelData }
                    }
                }
            }
            Rectangle {
                id: viewport
                Layout.fillWidth: true; Layout.fillHeight: true
                color: "#0b0914"; radius: 16; border.color: "#26223a"; clip: true
                Item {
                    id: stage
                    anchors.centerIn: parent
                    property real factor: picture.sourceSize.width > 0 ? Math.min((viewport.width-24)/picture.sourceSize.width, (viewport.height-24)/picture.sourceSize.height) : 1
                    width: picture.sourceSize.width * factor
                    height: picture.sourceSize.height * factor
                    Image {
                        id: picture
                        anchors.fill: parent
                        source: root.sourcePath ? "file://" + root.sourcePath.split("/").map(encodeURIComponent).join("/") : ""
                        fillMode: Image.PreserveAspectFit
                        onStatusChanged: drawing.requestPaint()
                    }
                    Canvas {
                        id: drawing
                        anchors.fill: parent
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset(); ctx.clearRect(0,0,width,height)
                            ctx.scale(stage.factor,stage.factor)
                            const all = root.current ? root.marks.concat([root.current]) : root.marks
                            for (const mark of all) {
                                const pts = mark.points
                                if (!pts.length) continue
                                const a = pts[0], b = pts[pts.length-1]
                                ctx.strokeStyle = mark.color; ctx.fillStyle = mark.color; ctx.lineWidth = mark.width
                                ctx.lineCap = "round"; ctx.lineJoin = "round"
                                if (mark.tool === "rectangle") ctx.strokeRect(a.x,a.y,b.x-a.x,b.y-a.y)
                                else if (mark.tool === "redact") { ctx.fillStyle = "#07060d"; ctx.fillRect(Math.min(a.x,b.x),Math.min(a.y,b.y),Math.abs(b.x-a.x),Math.abs(b.y-a.y)) }
                                else {
                                    ctx.beginPath(); ctx.moveTo(a.x,a.y)
                                    for (const point of pts) ctx.lineTo(point.x,point.y)
                                    ctx.stroke()
                                    if (mark.tool === "arrow") {
                                        const angle = Math.atan2(b.y-a.y,b.x-a.x), len = Math.max(14,mark.width*4)
                                        ctx.beginPath(); ctx.moveTo(b.x,b.y)
                                        ctx.lineTo(b.x-len*Math.cos(angle-.5),b.y-len*Math.sin(angle-.5))
                                        ctx.lineTo(b.x-len*Math.cos(angle+.5),b.y-len*Math.sin(angle+.5))
                                        ctx.closePath(); ctx.fill()
                                    }
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent; enabled: root.editing && !exporter.running
                            cursorShape: Qt.CrossCursor
                            function point(mouse) { return {x: Math.max(0,Math.min(picture.sourceSize.width,mouse.x/stage.factor)), y: Math.max(0,Math.min(picture.sourceSize.height,mouse.y/stage.factor))} }
                            onPressed: mouse => { root.current = {tool:root.tool,color:root.ink,width:5,points:[point(mouse)]}; drawing.requestPaint() }
                            onPositionChanged: mouse => {
                                if (!pressed || !root.current) return
                                const mark = root.current
                                mark.points = mark.tool === "pen" ? mark.points.concat([point(mouse)]) : [mark.points[0],point(mouse)]
                                root.current = mark; drawing.requestPaint()
                            }
                            onReleased: { if (root.current) root.marks = root.marks.concat([root.current]); root.current = null; drawing.requestPaint() }
                            onCanceled: { root.current = null; drawing.requestPaint() }
                        }
                    }
                }
            }
            RowLayout {
                id: uploadSettings
                visible: false; Layout.fillWidth: true
                Text { font.family: "Cellforge"; text: "Upload endpoint"; color: "#9a96b3" }
                TextField { font.family: "Cellforge"; id: endpoint; text: "guns.lol"; Layout.fillWidth: true; placeholderText: "https://your-host/upload (multipart field: file)"; color: "#f2f0ff"; background: Rectangle { radius: 8; color: "#1a1630"; border.color: "#b46bff" } }
            }
            RowLayout {
                visible: uploadSettings.visible; Layout.fillWidth: true
                TextField { font.family: "Cellforge";
                    id: configFile; Layout.fillWidth: true
                    placeholderText: "~/Downloads/guns-lol.sxcu (dashboard uploader config)"
                    color: "#f2f0ff"
                    background: Rectangle { radius: 8; color: "#1a1630"; border.color: "#b46bff" }
                }
                GalaxyButton {
                    text: "Import guns.lol"; enabled: !importer.running && configFile.text.length > 0
                    onClicked: { importer.command = ["python3", Quickshell.shellPath("uploader.py"), configFile.text]; importer.running = true; endpoint.text = "guns.lol" }
                }
                GalaxyButton { text: "Dashboard ↗"; onClicked: Qt.openUrlExternally("https://guns.lol/imagehost/setup") }
            }
            Text { font.family: "Cellforge"; Layout.fillWidth: true; text: root.message; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: "#9a96b3"; font.pixelSize: 12 }
        }
    }
}
