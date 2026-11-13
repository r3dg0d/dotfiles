#!/usr/bin/env python3
"""Load a Galaxy widget's shell.qml against the Quickshell stand-in. See README.md."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path

from PySide6.QtCore import Property, QByteArray, QObject, QProcess, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QJSValue, QmlAttached, QmlElement, QQmlApplicationEngine, qmlRegisterType

HERE = Path(__file__).resolve().parent
SHELL_DIR = Path()
IPC: dict[str, QObject] = {}
LAYER: dict[str, object] = {}


class QuickshellGlobal(QObject):
    @Slot(str, result=str)
    def shellPath(self, name: str) -> str:
        return str(SHELL_DIR / name)

    @Slot(str, result=str)
    def env(self, name: str) -> str:
        return os.environ.get(name, "")

    @Slot("QVariant")
    def execDetached(self, command) -> None:
        argv = command.toVariant() if isinstance(command, QJSValue) else command
        QProcess.startDetached(argv[0], list(argv[1:]))

    @Slot(str, result=str)
    def iconPath(self, name: str) -> str:
        return ""


class StdioCollector(QObject):
    streamFinished = Signal()
    textChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._text = ""

    @Property(str, notify=textChanged)
    def text(self) -> str:
        return self._text

    def feed(self, data: bytes) -> None:
        self._text += data.decode("utf-8", "replace")

    def finish(self) -> None:
        self.textChanged.emit()
        self.streamFinished.emit()
        self._text = ""


class SplitParser(QObject):
    read = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._buf = b""

    def feed(self, data: bytes) -> None:
        self._buf += data
        *lines, self._buf = self._buf.split(b"\n")
        for line in lines:
            self.read.emit(line.decode("utf-8", "replace"))

    def finish(self) -> None:
        if self._buf:
            self.read.emit(self._buf.decode("utf-8", "replace"))
        self._buf = b""


class Process(QObject):
    runningChanged = Signal()
    commandChanged = Signal()
    stdoutChanged = Signal()
    started = Signal()
    exited = Signal(int, int, arguments=["exitCode", "exitStatus"])

    def __init__(self, parent=None):
        super().__init__(parent)
        self._command: list[str] = []
        self._running = False
        self._stdout: QObject | None = None
        self._proc: QProcess | None = None

    def _get_command(self):
        return self._command

    def _set_command(self, value):
        self._command = [str(v) for v in (value.toVariant() if isinstance(value, QJSValue) else value or [])]
        self.commandChanged.emit()

    command = Property("QVariant", _get_command, _set_command, notify=commandChanged)

    def _get_stdout(self):
        return self._stdout

    def _set_stdout(self, obj):
        self._stdout = obj
        self.stdoutChanged.emit()

    stdout = Property(QObject, _get_stdout, _set_stdout, notify=stdoutChanged)

    def _get_running(self):
        return self._running

    def _set_running(self, on: bool):
        if on and not self._running:
            QTimer.singleShot(0, self._start)  # after bindings settle, like Quickshell
            self._running = True
            self.runningChanged.emit()
        elif not on and self._running and self._proc is not None:
            self._proc.terminate()

    running = Property(bool, _get_running, _set_running, notify=runningChanged)

    def _start(self):
        if not self._command:
            self._done(127, 0)
            return
        self._proc = QProcess(self)
        self._proc.readyReadStandardOutput.connect(self._read)
        self._proc.finished.connect(lambda code, status: self._done(code, int(status.value)))
        self._proc.errorOccurred.connect(lambda err: self._done(127, 1) if self._proc and self._proc.state() == QProcess.NotRunning else None)
        self._proc.start(self._command[0], self._command[1:])
        self.started.emit()

    def _read(self):
        data = bytes(self._proc.readAllStandardOutput())
        if self._stdout is not None:
            self._stdout.feed(data)

    def _done(self, code, status):
        if not self._running:
            return
        if self._proc is not None:
            self._read()
        if self._stdout is not None:
            self._stdout.finish()
        self._running = False
        self._proc = None
        self.runningChanged.emit()
        self.exited.emit(code, status)

    @Slot()
    def signal_(self):
        pass


class FileView(QObject):
    loaded = Signal()
    loadFailed = Signal(int)
    pathChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._path = ""
        self._text = ""
        self._print = True

    def _get_path(self):
        return self._path

    def _set_path(self, value):
        self._path = str(value).removeprefix("file://")
        self.pathChanged.emit()
        QTimer.singleShot(0, self.reload)

    path = Property(str, _get_path, _set_path, notify=pathChanged)
    printErrors = Property(bool, lambda self: self._print, lambda self, v: setattr(self, "_print", v))
    watchChanges = Property(bool, lambda self: False, lambda self, v: None)

    @Slot()
    def reload(self):
        try:
            self._text = Path(self._path).read_text(encoding="utf-8")
        except OSError:
            self.loadFailed.emit(1)
            return
        self.loaded.emit()

    @Slot(result=str)
    def text(self) -> str:
        return self._text

    @Slot(str)
    def setText(self, text: str):
        Path(self._path).parent.mkdir(parents=True, exist_ok=True)
        Path(self._path).write_text(text, encoding="utf-8")
        self._text = text


class IpcHandler(QObject):
    targetChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._target = ""

    def _set_target(self, value):
        self._target = value
        IPC[value] = self
        self.targetChanged.emit()

    target = Property(str, lambda self: self._target, _set_target, notify=targetChanged)


QML_IMPORT_NAME = "Quickshell.Wayland"
QML_IMPORT_MAJOR_VERSION = 1


class LayerAttached(QObject):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._v = {}

    def _get(self, name):
        return self._v.get(name)

    def _set(self, name, value):
        self._v[name] = value
        LAYER[name] = value
        self.changed.emit()

    namespace = Property("QVariant", lambda s: s._get("namespace"), lambda s, v: s._set("namespace", v), notify=changed)
    layer = Property("QVariant", lambda s: s._get("layer"), lambda s, v: s._set("layer", v), notify=changed)
    keyboardFocus = Property("QVariant", lambda s: s._get("keyboardFocus"), lambda s, v: s._set("keyboardFocus", v), notify=changed)
    exclusiveZone = Property("QVariant", lambda s: s._get("exclusiveZone"), lambda s, v: s._set("exclusiveZone", v), notify=changed)


@QmlElement
@QmlAttached(LayerAttached)
class WlrLayershell(QObject):
    @staticmethod
    def qmlAttachedProperties(self, obj):
        return LayerAttached(obj)


def call_ipc(target: str, fn: str, *args):
    """Invoke an IpcHandler function the way `quickshell ipc call TARGET FN ARGS` does (string arguments, typed by the function)."""
    from PySide6.QtQml import QQmlExpression, qmlContext

    handler = IPC.get(target)
    if handler is None:
        raise SystemExit(f"no IPC target {target!r}; have {sorted(IPC)}")
    meta = handler.metaObject()
    for i in range(meta.methodCount()):
        m = meta.method(i)
        if bytes(m.name()).decode() == fn and m.parameterCount() == len(args):
            conv = []
            for j, a in enumerate(args):
                t = bytes(m.parameterTypeName(j)).decode()
                conv.append(json.dumps(int(a) if t == "int" else float(a) if t in ("double", "qreal") else (a in ("1", "true")) if t == "bool" else a))
            expr = QQmlExpression(qmlContext(handler), handler, f"{fn}({', '.join(conv)})")
            out = expr.evaluate()
            if expr.hasError():
                raise SystemExit(f"IPC {target}.{fn}: {expr.error().toString()}")
            return out
    raise SystemExit(f"no IPC function {target}.{fn}/{len(args)}")


def main() -> int:
    global SHELL_DIR
    ap = argparse.ArgumentParser()
    ap.add_argument("widget", help="directory name under config/quickshell, or a path")
    ap.add_argument("--call", action="append", default=[], metavar="TARGET.FN[:ARG,...]", help="IPC call; repeatable, run in order")
    ap.add_argument("--wait", type=float, default=0.4, help="seconds to let processes and animations settle after each call")
    ap.add_argument("--shot", help="write a PNG of the first visible window after the calls")
    ap.add_argument("--eval", action="append", default=[], help="print a JS expression evaluated on the ShellRoot after the calls (as `root`)")
    ap.add_argument("--size", default="1600x900")
    args = ap.parse_args()

    src = Path(args.widget)
    if not src.is_dir():
        src = HERE.parent.parent / "config" / "quickshell" / args.widget
    work = Path(tempfile.mkdtemp(prefix="qs-harness-"))
    SHELL_DIR = work / src.name
    shutil.copytree(src, SHELL_DIR, symlinks=True)
    singletons = [p.stem for p in SHELL_DIR.glob("*.qml") if p.read_text(encoding="utf-8").lstrip().startswith("pragma Singleton")]
    if singletons:  # Quickshell registers these implicitly; plain Qt needs a qmldir
        (SHELL_DIR / "qmldir").write_text("".join(f"singleton {n} 1.0 {n}.qml\n" for n in singletons)
                                          + "".join(f"{p.stem} 1.0 {p.name}\n" for p in SHELL_DIR.glob("*.qml") if p.stem not in singletons and p.stem != "shell"))

    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    app = QGuiApplication(sys.argv[:1])
    errors: list[str] = []
    engine = QQmlApplicationEngine()
    engine.warnings.connect(lambda ws: errors.extend(w.toString() for w in ws))
    engine.addImportPath(str(HERE / "stubs"))
    glob = QuickshellGlobal()
    # Exposed through a QML singleton (stubs/Quickshell/QuickshellGlobal.qml): registering the Python
    # object as a singleton instance directly breaks Canvas items in PySide6 6.12.
    engine.rootContext().setContextProperty("__qsGlobal", glob)
    for cls in (Process, StdioCollector, SplitParser, FileView, IpcHandler):
        qmlRegisterType(cls, "Quickshell.Io", 1, 0, cls.__name__)
    engine.load(QUrl.fromLocalFile(str(SHELL_DIR / "shell.qml")))
    if not engine.rootObjects():
        print("LOAD FAILED\n" + "\n".join(errors))
        return 1
    root = engine.rootObjects()[0]
    w, h = (int(x) for x in args.size.split("x"))

    def settle(seconds: float) -> None:
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            app.processEvents()
            time.sleep(0.01)

    def windows():
        return [x for x in app.allWindows() if x.inherits("QQuickWindow")]

    for win in windows():
        win.resize(w, h)
    settle(args.wait)
    for spec in args.call:
        name, _, rest = spec.partition(":")
        target, _, fn = name.partition(".")
        call_ipc(target, fn, *([a.replace("\\c", ",") for a in rest.split(",")] if rest else []))
        settle(args.wait)
    from PySide6.QtQml import QQmlExpression

    for expr in args.eval:
        e = QQmlExpression(engine.rootContext(), root, expr.replace("root.", "this."))
        value = e.evaluate()
        if isinstance(value, tuple):
            value = value[0]
        if isinstance(value, QJSValue):
            value = value.toVariant()
        print(json.dumps(value, ensure_ascii=False, default=str))
    if args.shot:
        vis = [x for x in windows() if x.isVisible()]
        if not vis:
            print("no visible window to capture")
        else:
            # Grab from the QML side (works whatever Python wrapper type the window has).
            from PySide6.QtQml import QQmlExpression as _E, qmlContext as _ctx

            target = json.dumps(args.shot)
            e = _E(_ctx(vis[0]) or engine.rootContext(), vis[0],
                   f"contentItem.grabToImage(function(r) {{ r.saveToFile({target}) }})")
            e.evaluate()
            if e.hasError():
                print("screenshot failed:", e.error().toString())
            settle(1.0)
    print(json.dumps({"layer": {k: str(v) for k, v in LAYER.items()}, "ipc_targets": sorted(IPC),
                      "visible_windows": sum(x.isVisible() for x in windows()), "warnings": errors}, ensure_ascii=False))
    shutil.rmtree(work, ignore_errors=True)
    return 1 if any("Error" in e or "is not" in e or "Cannot" in e or "Unable" in e for e in errors) else 0


if __name__ == "__main__":
    sys.exit(main())
