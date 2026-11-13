# qs-harness

A stand-in for the parts of Quickshell the Galaxy widgets use, so their QML can be loaded,
driven and screenshotted on a machine without Quickshell or a Wayland session (CI, a container).

It is **not** Quickshell. It checks that a widget's QML loads without errors against Qt 6, that its
logic and backend scripts work when driven through the same `IpcHandler` functions the launchers
call, and what it looks like. It cannot check layer-shell placement, keyboard focus handover or
compositor key bindings; those need the real desktop.

    pip install PySide6
    QT_QPA_PLATFORM=offscreen python3 tools/qs-harness/run.py galaxy-emoji --call emoji.open --shot /tmp/emoji.png

`Process`, `FileView` and `Quickshell.execDetached` are real (they run the widget's own scripts);
`PanelWindow` is an ordinary window; `WlrLayershell.*` assignments are accepted and recorded.
