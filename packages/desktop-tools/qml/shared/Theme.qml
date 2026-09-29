pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Mirrors Ambxst's look without depending on Ambxst: the same matugen palette
// (~/.cache/ambxst/colors.json, rewritten on every wallpaper change) and the
// same theme settings (~/.config/ambxst/config/theme.json). Both files are
// watched, so the widgets and apps follow wallpaper/OLED changes live.
Singleton {
    id: root

    property var c: ({})
    property var t: ({})

    FileView {
        path: Quickshell.env("HOME") + "/.cache/ambxst/colors.json"
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: { try { root.c = JSON.parse(text()); } catch (e) {} }
    }
    FileView {
        path: Quickshell.env("HOME") + "/.config/ambxst/config/theme.json"
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: { try { root.t = JSON.parse(text()); } catch (e) {} }
    }

    function col(name, fallback) { return c[name] !== undefined ? c[name] : fallback; }

    // Matrix / Dotsquared identity tokens — see config/theme-seeds/zionsec-matrix-tokens.json
    // (used as fallbacks when Ambxst
    // matugen colours are missing, and as named aliases for QML). Near-black,
    // matrix-green accents, amber warn, red critical — usable, not cheesy.
    // Canonical seed: config/theme-seeds/zionsec-matrix-tokens.json
    readonly property color matrixBg: "#050805"
    readonly property color matrixSurface: "#0a100c"
    readonly property color matrixGreen: "#00c853"       // Material primary / soft accent
    readonly property color matrixGreenDim: "#1b5e20"
    readonly property color matrixGreenSoft: "#69f0ae"   // success
    readonly property color matrixPhosphor: "#00ff66"    // Ghostty / MatrixShot luminous
    readonly property color matrixAmber: "#ffb300"       // warn
    readonly property color matrixRed: "#ff5252"         // critical
    readonly property color matrixCyan: "#18ffff"
    readonly property color matrixBorder: "#1a3d28"
    readonly property color matrixLuminous: "#00ff66"    // aligned to phosphor

    readonly property bool oled: t.oledMode === true
    readonly property color background: oled ? "#000000" : col("background", matrixBg)
    readonly property color surface: col("surface", matrixSurface)
    readonly property color surfaceDim: col("surfaceDim", matrixSurface)
    readonly property color surfaceContainer: col("surfaceContainer", "#0f1812")
    readonly property color surfaceHigh: col("surfaceContainerHigh", "#152019")
    readonly property color surfaceBright: col("surfaceBright", "#1c2a22")
    readonly property color surfaceVariant: col("surfaceVariant", matrixBorder)
    readonly property color outline: col("outline", "#5a7a62")
    readonly property color outlineVariant: col("outlineVariant", matrixBorder)
    readonly property color fg: col("overBackground", "#d8ffe8")
    readonly property color fgDim: col("overSurfaceVariant", "#8fb89a")
    readonly property color primary: col("primary", matrixGreen)
    readonly property color onPrimary: col("overPrimary", "#003910")
    readonly property color primaryContainer: col("primaryContainer", matrixGreenDim)
    readonly property color secondary: col("secondary", matrixGreenSoft)
    readonly property color tertiary: col("tertiary", matrixCyan)
    readonly property color error: col("error", matrixRed)
    readonly property color errorContainer: col("errorContainer", "#5c0000")
    readonly property color warning: col("yellow", matrixAmber)
    readonly property color ok: col("green", matrixGreenSoft)
    // Ambxst's halftone "bg" style: dark base with a fine dot grid.
    readonly property color dot: Qt.rgba(surface.r, surface.g, surface.b, 0.95)
    readonly property color border: surfaceVariant
    // Thin luminous border for cards/modals (Matrix accent when Ambxst absent).
    readonly property color popupBorder: col("surfaceTint", matrixLuminous)
    readonly property color luminous: popupBorder

    readonly property string font: t.font || "sans-serif"
    // Prefer a monospace stack for Matrix look; Ambxst monoFont wins when set.
    readonly property string mono: t.monoFont || "JetBrains Mono, Cascadia Code, ui-monospace, monospace"
    readonly property string icons: "Phosphor-Bold"
    readonly property int roundness: t.roundness !== undefined ? t.roundness : 0
    function radius(offset) { return roundness > 0 ? Math.max(roundness + offset, 0) : 0; }
    readonly property int anim: t.animDuration !== undefined ? t.animDuration : 300

    readonly property int fs: 13
    readonly property int fsSmall: 11
    readonly property int fsBig: 16
    readonly property int fsHuge: 26

    // Phosphor-Bold codepoints (same font Ambxst uses).
    readonly property string iSync: ""
    readonly property string iDisk: ""
    readonly property string iHdd: ""
    readonly property string iTrash: ""
    readonly property string iBroom: ""
    readonly property string iFolder: ""
    readonly property string iFile: ""
    readonly property string iInfo: ""
    readonly property string iAlert: ""
    readonly property string iCheck: ""
    readonly property string iX: ""
    readonly property string iLaunch: ""
    readonly property string iCube: ""
    readonly property string iGear: ""
    readonly property string iShield: ""
    readonly property string iDown: ""
    readonly property string iUndo: ""
    readonly property string iSpinner: ""
    readonly property string iPower: ""
    readonly property string iEye: ""
    readonly property string iList: ""
    readonly property string iCaretDown: ""
    readonly property string iCaretRight: ""
    readonly property string iGamepad: ""
    readonly property string iRobot: ""
    readonly property string iCpu: ""

    function bytes(b) {
        if (b === undefined || b === null || isNaN(b)) return "—";
        const u = ["B", "KB", "MB", "GB", "TB", "PB"];
        let v = Number(b), i = 0;
        while (v >= 1000 && i < u.length - 1) { v /= 1000; i++; }
        return i === 0 ? v + " B" : (v >= 100 ? v.toFixed(0) : v.toFixed(1)) + " " + u[i];
    }
    function ago(unix) {
        if (!unix) return "never";
        const s = Math.floor(Date.now() / 1000) - unix;
        if (s < 60) return "just now";
        if (s < 3600) return Math.floor(s / 60) + " min ago";
        if (s < 86400) return Math.floor(s / 3600) + " h ago";
        return Math.floor(s / 86400) + " d ago";
    }
    function date(unix) {
        if (!unix) return "—";
        return Qt.formatDateTime(new Date(unix * 1000), "yyyy-MM-dd hh:mm");
    }
}
