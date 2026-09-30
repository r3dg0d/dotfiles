-- Execute configuration with inert Hyprland dispatchers; never start programs.
local function inert()
    return setmetatable({}, {
        __index = function(self, key)
            local value = inert()
            rawset(self, key, value)
            return value
        end,
        __call = function() return inert() end,
    })
end
local vars, binds = {}, {}
hl = inert()
hl.env = function(name, value) vars[name] = value end
hl.bind = function(key, command) binds[key] = command end
hl.dsp.exec_cmd = function(command) return command end
local getenv = os.getenv
os.getenv = function(name)
    if name == "HOME" then return "/tmp/test home" end
    if name == "PATH" then return "/example/bin" end
    return getenv(name)
end
dofile(assert(arg[1], "configuration path is required"))
assert(vars.PATH == "/tmp/test home/.local/bin:/example/bin")
assert(binds.Print == "matrixshot choose")
assert(binds["CTRL + SHIFT + Print"] == "matrixshot record toggle")
assert(binds["SUPER + SHIFT + PERIOD"] == "keystroke-noise toggle")
assert(binds["SUPER + ALT + S"]:find('"$HOME/Pictures/Screenshots"', 1, true))
assert(binds["SUPER + ALT + R"]:find('"$HOME/Videos/Recordings"', 1, true))
print("Desktop paths and capture bindings passed with a custom home containing spaces")
