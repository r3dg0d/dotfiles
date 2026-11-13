pragma Singleton
import QtQml
QtObject {
    // __qsGlobal goes away during teardown; bindings that re-evaluate then get an empty answer.
    function shellPath(name) { return __qsGlobal ? __qsGlobal.shellPath(name) : "" }
    function env(name) { return __qsGlobal ? __qsGlobal.env(name) : "" }
    function execDetached(command) { if (__qsGlobal) __qsGlobal.execDetached(command) }
    function iconPath(name) { return "" }
}
