#!/usr/bin/env python3
"""Backend for the galaxy-vm Quickshell apps. Wraps windowsvm / linuxvm / androidvm (vmtools).

  vm.py state                      JSON: vms, host checks, docker availability
  vm.py act <kind> <verb> <name>   start|stop|shutdown|reboot|restart|gui|delete (runs the CLI detached)
  vm.py term <command...>          run a CLI command in a Ghostty terminal (wizards, setup, fixes)
  vm.py log <kind> [n]             tail of the GUI action log for that kind
"""
import json, os, re, shlex, subprocess, sys, time
from pathlib import Path

HOME = Path.home()
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "vmtools"
LOGS = DATA / "logs"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "galaxy-vm"
URI = "qemu:///session"
TOOLS = {"windows": "windowsvm", "linux": "linuxvm", "android": "androidvm", "ios": "iosvm", "macos": "macosvm"}
APPLE = ("ios", "macos")
RUN_TOOL = HOME / "src/vmtools/bin/run-tool.py"


def cli(tool):
    """Installed CLI, else the ~/src/vmtools checkout (iosvm/macosvm before the package is rebuilt)."""
    import shutil
    if shutil.which(tool) or not RUN_TOOL.exists():
        return [tool]
    return ["python3", str(RUN_TOOL), tool]


def apple_vms(kind):
    rc, o, _ = sh(cli(TOOLS[kind]) + ["--json", "list"], timeout=20)
    try:
        rows = json.loads(o) if rc == 0 else []
    except ValueError:
        rows = []
    out = []
    for r in rows:
        out.append({"kind": kind, "name": r["name"], "state": r["state"], "cpus": r.get("cpus"),
                    "ram_mb": r.get("rss_mib") or (r.get("ram_gib") or 0) * 1024, "uptime_s": r.get("uptime_s"), "cpu_pct": None,
                    "display": "console" if kind == "ios" else ("X11" if r.get("backend") == "docker-osx" else "VNC"),
                    "detail": (r.get("device") or "") if kind == "ios" else f"{r.get('version', '')} · {r.get('backend', 'qemu')}"})
    return out
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def sh(cmd, timeout=15):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, ANSI.sub("", p.stdout), ANSI.sub("", p.stderr)
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, "", str(e)


def docker_env():
    env = dict(os.environ)
    sock = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "docker.sock"
    if "DOCKER_HOST" not in env and sock.exists():
        env["DOCKER_HOST"] = f"unix://{sock}"
    return env


def docker_ok():
    try:
        return subprocess.run(["docker", "info"], capture_output=True, timeout=5, env=docker_env()).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def doctor(kind):
    """Parse '✓ Name   OK   detail' rows; cached 60s (doctor is read-only)."""
    CACHE.mkdir(parents=True, exist_ok=True)
    cf = CACHE / f"doctor-{kind}.json"
    if cf.exists() and time.time() - cf.stat().st_mtime < 60:
        try:
            return json.loads(cf.read_text())
        except ValueError:
            pass
    if kind in APPLE:
        rc, o, _ = sh(cli(TOOLS[kind]) + ["--json", "doctor"], timeout=30)
        try:
            rep = json.loads(o)
            rows = [{"name": c["name"], "ok": c["status"] == "ok", "warn": c["status"] == "warn", "detail": c["detail"], "hint": c["hint"]}
                    for sec in rep["sections"] for c in sec["checks"]]
        except (ValueError, KeyError):
            rows = [{"name": f"{TOOLS[kind]} doctor", "ok": False, "detail": "could not run"}]
        cf.write_text(json.dumps(rows))
        return rows
    _, out, err = sh([TOOLS[kind], "doctor"], timeout=30)
    rows = []
    for line in (out + err).splitlines():
        m = re.match(r"\s*([✓✗!])\s+(.+?)\s{2,}(OK|FAIL|WARN)\s*(.*)$", line)
        if m:
            rows.append({"name": m.group(2).strip(), "ok": m.group(3) == "OK", "detail": m.group(4).strip()})
    cf.write_text(json.dumps(rows))
    return rows


def fix_for(kind, name):
    n = name.lower()
    if kind in APPLE:
        assets = "nix-build ~/src/vmtools/nix/apple-assets.nix -o ~/.local/share/vmtools/apple/assets"
        table = [
            ("ignore_msrs", ["info", "Staged: ~/rice-staging/r3dg0d-applevm.nix (kvm ignore_msrs=1) — import it in configuration.nix, rebuild, reboot"]),
            ("dmg2img", ["term", "nix profile install nixpkgs#dmg2img"]),
            ("7-zip", ["term", "nix profile install nixpkgs#_7zz"]),
            ("vnc viewer", ["term", "nix profile install nixpkgs#virt-viewer"]),
            ("qemu-sptm", ["term", "nix-build -E 'with import <nixpkgs> {}; callPackage ~/src/vmtools/nix/qemu-sptm.nix {}' -o ~/.local/share/vmtools/apple/qemu-sptm"
                                   " && iosvm config ios_qemu ~/.local/share/vmtools/apple/qemu-sptm/bin/qemu-system-aarch64"]),
            ("ipsw", ["term", "nix profile install nixpkgs#ipsw"]),
            ("jq", ["term", "nix profile install nixpkgs#jq"]),
            ("socat", ["term", "nix profile install nixpkgs#socat"]),
            ("osx-kvm", ["term", assets]), ("darwin-vm", ["term", assets]),
            ("opencore", ["term", assets]), ("ovmf", ["term", assets]),
            ("docker", ["info", "Needs rootless Docker: install ~/rice-staging/r3dg0d-docker.nix (see sudo steps), re-login"]),
            ("install media", ["info", "User-supplied: copy BaseSystem.dmg / an installer image from your Mac, then Import (or: macosvm fetch-recovery sonoma) — docs/MACOSVM.md"]),
            ("firmware set", ["info", "User-supplied: on the Mac run darwin-vm ./get_files.sh && ./fix_perms.sh, copy firmware/ here, then Import — docs/IOSVM.md"]),
            ("unpatched", ["info", "Finish the ramdisk patch on the Mac (fix_perms.sh) — docs/IOSVM.md"]),
            ("installers needing", ["term", "macosvm imports"]),
        ]
        for key, fix in table:
            if key in n:
                return fix
        return ["term", f"{TOOLS[kind]} doctor"]
    if n == "adb":
        return ["term", "nix profile install nixpkgs#android-tools"]
    if "pro access" in n or "credentials" in n:
        return ["term", "bash ~/rice-staging/android-pro-setup.sh"]
    if n == "docker" or "docker" in n:
        return ["info", "Needs rootless Docker: install ~/rice-staging/r3dg0d-docker.nix (see sudo steps), re-login"]
    if "libvirt" in n or "kvm" in n:
        return ["info", "Group/daemon fix is in ~/rice-staging/r3dg0d-widgets.nix; rebuild + re-login"]
    return ["term", f"{TOOLS[kind]} doctor"]


def cpu_cache():
    f = CACHE / "cpu.json"
    try:
        return json.loads(f.read_text())
    except (OSError, ValueError):
        return {}


def libvirt_vms(kind, prev, now):
    out = []
    for meta_path in sorted((DATA / "metadata").glob("vm-*.json")):
        try:
            meta = json.loads(meta_path.read_text())
        except ValueError:
            continue
        if meta.get("os") != kind:
            continue
        name = meta.get("name") or meta_path.stem[3:]
        vm = {"kind": kind, "name": name, "state": "missing", "cpus": meta.get("cpus"), "ram_mb": (meta.get("ram_gib") or 0) * 1024,
              "uptime_s": None, "cpu_pct": None, "display": "virt-viewer", "detail": meta.get("distro") or meta.get("media_id") or ""}
        rc, info, _ = sh(["virsh", "-c", URI, "dominfo", name])
        if rc == 0:
            kv = dict((k.strip(), v.strip()) for k, v in (l.split(":", 1) for l in info.splitlines() if ":" in l))
            vm["state"] = kv.get("State", "?")
            vm["cpus"] = int(kv.get("CPU(s)", vm["cpus"] or 0) or 0)
            mem = re.match(r"(\d+)", kv.get("Used memory", kv.get("Max memory", "")))
            if mem:
                vm["ram_mb"] = int(mem.group(1)) // 1024
            t = re.match(r"([\d.]+)s", kv.get("CPU time", ""))
            if t and vm["state"] == "running":
                cpu_t = float(t.group(1)); key = f"{kind}/{name}"
                if key in prev and now > prev[key][1]:
                    vm["cpu_pct"] = round(100 * (cpu_t - prev[key][0]) / (now - prev[key][1]) / max(1, vm["cpus"] or 1), 1)
                prev[key] = [cpu_t, now]
                pid = HOME / ".config/libvirt/qemu/run" / f"{name}.pid"
                if pid.exists():
                    vm["uptime_s"] = int(now - pid.stat().st_mtime)
        out.append(vm)
    return out


def android_vms(dok):
    out = []
    for path in sorted((DATA / "android").glob("*.json")):
        if path.name.endswith("-ports.json") or path.name == "access.json":
            continue
        try:
            meta = json.loads(path.read_text())
        except ValueError:
            continue
        vm = {"kind": "android", "name": meta.get("name", path.stem), "state": "stopped" if dok else "docker offline",
              "cpus": None, "ram_mb": None, "uptime_s": None, "cpu_pct": None, "display": "noVNC",
              "viewer": "http://" + meta.get("viewer", ""), "adb": meta.get("adb"), "detail": meta.get("tag", "")}
        if dok:
            env = docker_env()
            rc, o, _ = sh(["docker", "inspect", "-f", "{{.State.Status}} {{.State.StartedAt}}", meta.get("container", "")])
            if rc == 0 and o.strip():
                st, started = o.split()[0], o.split()[1]
                vm["state"] = "running" if st == "running" else st
                if st == "running":
                    try:
                        from datetime import datetime
                        vm["uptime_s"] = int(time.time() - datetime.fromisoformat(started[:26].rstrip("Z") + "+00:00").timestamp())
                    except ValueError:
                        pass
                    rc, s, _ = sh(["docker", "stats", "--no-stream", "--format", "{{.CPUPerc}} {{.MemUsage}}", meta["container"]])
                    m = re.match(r"([\d.]+)%\s+([\d.]+)(MiB|GiB)", s.strip())
                    if m:
                        vm["cpu_pct"] = float(m.group(1)); vm["ram_mb"] = int(float(m.group(2)) * (1024 if m.group(3) == "GiB" else 1))
        out.append(vm)
    return out


def state():
    now = time.time()
    prev = cpu_cache()
    dok = docker_ok()
    vms = libvirt_vms("windows", prev, now) + libvirt_vms("linux", prev, now) + android_vms(dok) + apple_vms("ios") + apple_vms("macos")
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE / "cpu.json").write_text(json.dumps(prev))
    checks = {}
    for kind in TOOLS:
        rows = doctor(kind)
        for r in rows:
            if not r["ok"] and kind in APPLE:
                r["fix"] = fix_for(kind, r["name"])
            elif not r["ok"]:
                r["fix"] = fix_for(kind, r["name"])
        checks[kind] = rows
    if not dok:
        checks["android"].insert(0, {"name": "Docker daemon", "ok": False, "detail": "no daemon (rootless docker staged)",
                                     "fix": fix_for("android", "docker")})
    else:
        checks["android"].insert(0, {"name": "Docker daemon", "ok": True, "detail": docker_env().get("DOCKER_HOST", "default socket")})
    print(json.dumps({"ts": int(now), "vms": vms, "checks": checks, "docker": dok}))


def log_line(kind, text):
    LOGS.mkdir(parents=True, exist_ok=True)
    with open(LOGS / f"gui-{kind}.log", "a") as f:
        f.write(time.strftime("%Y-%m-%d %I:%M:%S %p ") + text + "\n")


def act(kind, verb, name):
    tool = TOOLS[kind]
    verbs = {"start": ["start"], "stop": ["stop"], "shutdown": ["shutdown"], "reboot": ["reboot"],
             "restart": ["restart"] if kind == "android" else ["reboot"], "gui": ["gui"], "delete": ["delete", "-y"]}
    if verb not in verbs:
        print(json.dumps({"ok": False, "error": f"unknown verb {verb}"})); return
    if kind == "ios" and verb == "gui":
        return term([f"iosvm console {shlex.quote(name)}"])
    if kind in APPLE:
        verbs["restart"] = ["stop"]  # no in-place reboot for direct-QEMU Apple guests
        verbs["gui"] = ["display"]
        verbs["reboot"] = ["stop"]
    cmd = cli(tool) + verbs[verb] + [name]
    log_line(kind, "$ " + " ".join(shlex.quote(c) for c in cmd))
    with open(LOGS / f"gui-{kind}.log", "a") as lf:
        subprocess.Popen(cmd, stdout=lf, stderr=lf, stdin=subprocess.DEVNULL, start_new_session=True, env=docker_env())
    print(json.dumps({"ok": True, "cmd": cmd}))


def term(args):
    script = " ".join(args)
    first = script.split(" ", 1)[0]
    if first in ("iosvm", "macosvm") and cli(first) != [first]:
        script = " ".join(shlex.quote(c) for c in cli(first)) + script[len(first):]
    body = (f"printf '\\033[38;2;180;107;255m✦ %s\\033[0m\\n\\n' {shlex.quote(script)}; {script}; s=$?; echo; "
            "[ $s -eq 0 ] && printf '\\033[38;2;125;255;168m✓ done\\033[0m\\n' || printf '\\033[38;2;255;92;138m✗ exit %s\\033[0m\\n' $s; "
            "read -rp 'Enter to close'")
    subprocess.Popen(["ghostty", "--title=Galaxy Construct", "-e", "bash", "-lc", body], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=docker_env())
    print(json.dumps({"ok": True, "launched": script}))


def log(kind, n=40):
    p = LOGS / f"gui-{kind}.log"
    lines = p.read_text(errors="replace").splitlines()[-int(n):] if p.exists() else ["(no actions yet)"]
    print(json.dumps({"lines": [ANSI.sub("", l) for l in lines]}))


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0] == "state":
        state()
    elif a[0] == "act" and len(a) == 4:
        act(a[1], a[2], a[3])
    elif a[0] == "term":
        term(a[1:])
    elif a[0] == "log":
        log(a[1], a[2] if len(a) > 2 else 40)
    else:
        print(__doc__); sys.exit(2)
