//@ pragma UseQApplication
//@ pragma ShellId storage-optimizer
//@ pragma DataDir $BASE/storage-optimizer
//@ pragma StateDir $BASE/storage-optimizer

// Storage Optimizer — standalone application window (launched by
// `storage-optimizer [page]`). Runs only while open; never scans in the
// background.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.shared
import qs.storage

ShellRoot {
    FloatingWindow {
        id: win
        title: "Storage Optimizer"
        implicitWidth: 1240
        implicitHeight: 840
        minimumSize: Qt.size(760, 560)
        color: Theme.background
        visible: true

        StorageApp {
            id: appView
            anchors.fill: parent
            startPage: Quickshell.env("ZS_START_PAGE") || "overview"
        }

        onVisibleChanged: {
            if (visible) return;
            if (StorageState.cleaning) visible = true;
            else Qt.quit();
        }
    }

    IpcHandler {
        target: "app"
        function open(page: string): void { win.visible = true; if (page) appView.showPage(page); }
    }
}
