//@ pragma UseQApplication
//@ pragma ShellId nixos-updater
//@ pragma DataDir $BASE/nixos-updater
//@ pragma StateDir $BASE/nixos-updater

// NixOS Updater — standalone application window (launched by `nixos-updater`
// from the app launcher or the bar widget). Runs only while open.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.shared
import qs.updater

ShellRoot {
    FloatingWindow {
        id: win
        title: "NixOS Updater"
        implicitWidth: 1180
        implicitHeight: 820
        minimumSize: Qt.size(720, 520)
        color: Theme.background
        visible: true

        UpdaterApp { anchors.fill: parent }

        // Closing while an update runs would orphan its progress view; keep
        // the window until the backend finishes. Otherwise quit entirely so
        // nothing stays resident.
        onVisibleChanged: {
            if (visible) return;
            if (UpdaterState.running) visible = true;
            else Qt.quit();
        }
    }

    IpcHandler {
        target: "app"
        function open(page: string): void { win.visible = true; }
    }
}
