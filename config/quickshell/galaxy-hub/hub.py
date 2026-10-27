#!/usr/bin/env python3
"""galaxy-hub backend: prints JSON for the quickshell panels and waybar modules.

Read-only by default. Anything that needs root is launched in a Ghostty window
(`term` actions) so the user types sudo themselves; no password is ever stored.
"""
import json, os, re, shlex, shutil, socket, subprocess, sys, time, urllib.request

HOME = os.path.expanduser("~")
CFG_DIR = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", HOME + "/.cache"), "galaxy-hub")
os.makedirs(CACHE, exist_ok=True)
UA = {"User-Agent": "galaxy-hub/1.0 (quickshell)"}


def cfg():
    try:
        with open(os.path.join(CFG_DIR, "config.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def run(cmd, timeout=10):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def fetch(url, timeout=8):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode(), r.geturl()


def cached(name, ttl, fn):
    path = os.path.join(CACHE, name + ".json")
    try:
        if time.time() - os.path.getmtime(path) < ttl:
            with open(path) as f:
                return json.load(f)
    except (OSError, ValueError):
        pass
    try:
        data = fn()
    except Exception as e:  # network down etc: fall back to stale cache
        try:
            with open(path) as f:
                data = json.load(f); data["stale"] = True; return data
        except (OSError, ValueError):
            return {"ok": False, "error": str(e)}
    with open(path + ".tmp", "w") as f:
        json.dump(data, f)
    os.replace(path + ".tmp", path)
    return data


def out(obj):
    print(json.dumps(obj))


# ── weather ──────────────────────────────────────────────────────────────
WMO = {0: ("Clear", "󰖙", "󰖔"), 1: ("Mostly clear", "󰖙", "󰖔"), 2: ("Partly cloudy", "󰖕", "󰼱"),
       3: ("Overcast", "󰖐", "󰖐"), 45: ("Fog", "󰖑", "󰖑"), 48: ("Rime fog", "󰖑", "󰖑"),
       51: ("Light drizzle", "󰖗", "󰖗"), 53: ("Drizzle", "󰖗", "󰖗"), 55: ("Heavy drizzle", "󰖗", "󰖗"),
       61: ("Light rain", "󰖗", "󰖗"), 63: ("Rain", "󰖖", "󰖖"), 65: ("Heavy rain", "󰙾", "󰙾"),
       71: ("Light snow", "󰖘", "󰖘"), 73: ("Snow", "󰼶", "󰼶"), 75: ("Heavy snow", "󰼶", "󰼶"),
       80: ("Showers", "󰖖", "󰖖"), 81: ("Showers", "󰖖", "󰖖"), 82: ("Violent showers", "󰙾", "󰙾"),
       95: ("Thunderstorm", "󰖓", "󰖓"), 96: ("Thunder + hail", "󰖓", "󰖓"), 99: ("Thunder + hail", "󰖓", "󰖓")}


def h12(hm):
    h, m = map(int, hm.split(":"))
    return f"{(h % 12) or 12}:{m:02d} {'AM' if h < 12 else 'PM'}"


def locate():
    c = cfg().get("weather", {})
    if "lat" in c and "lon" in c:
        return {"lat": c["lat"], "lon": c["lon"], "name": c.get("name", "configured"), "source": "config (lat/lon)"}
    if c.get("city"):
        q = urllib.parse.quote(c["city"])
        d = json.loads(fetch(f"https://geocoding-api.open-meteo.com/v1/search?name={q}&count=1")[0])
        r = d["results"][0]
        return {"lat": r["latitude"], "lon": r["longitude"], "name": f'{r["name"]}, {r.get("admin1", r.get("country", ""))}', "source": "config (city)"}
    d = json.loads(fetch("https://ipapi.co/json/")[0])
    note = "auto (IP geolocation)"
    m = run(["curl", "-s", "-m", "4", "https://am.i.mullvad.net/json"], 6)
    try:
        if json.loads(m).get("mullvad_exit_ip"):
            note = "auto (IP) — Mullvad exit, set weather.city in config.json"
    except ValueError:
        pass
    return {"lat": d["latitude"], "lon": d["longitude"], "name": f'{d.get("city")}, {d.get("region") or d.get("country_name")}', "source": note}


def weather():
    import urllib.parse  # noqa: F401  (used by locate)
    def get():
        loc = locate()
        units = cfg().get("weather", {}).get("units", "fahrenheit")
        u = "&temperature_unit=fahrenheit&wind_speed_unit=mph" if units == "fahrenheit" else ""
        url = (f"https://api.open-meteo.com/v1/forecast?latitude={loc['lat']}&longitude={loc['lon']}"
               "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"
               "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"
               f"&timezone=auto&forecast_days=5{u}")
        d = json.loads(fetch(url)[0])
        cur = d["current"]
        name, day_icon, night_icon = WMO.get(cur["weather_code"], ("—", "󰖐", "󰖐"))
        days = []
        for i, date in enumerate(d["daily"]["time"]):
            n, ic, _ = WMO.get(d["daily"]["weather_code"][i], ("—", "󰖐", "󰖐"))
            days.append({"date": date, "label": time.strftime("%a", time.strptime(date, "%Y-%m-%d")), "icon": ic, "desc": n,
                         "hi": round(d["daily"]["temperature_2m_max"][i]), "lo": round(d["daily"]["temperature_2m_min"][i]),
                         "rain": d["daily"]["precipitation_probability_max"][i]})
        unit = "°F" if units == "fahrenheit" else "°C"
        return {"ok": True, "location": loc["name"], "source": loc["source"], "unit": unit,
                "temp": round(cur["temperature_2m"]), "feels": round(cur["apparent_temperature"]),
                "humidity": cur["relative_humidity_2m"], "wind": round(cur["wind_speed_10m"]),
                "wind_unit": "mph" if units == "fahrenheit" else "km/h",
                "desc": name, "icon": day_icon if cur["is_day"] else night_icon,
                "sunrise": h12(d["daily"]["sunrise"][0][-5:]), "sunset": h12(d["daily"]["sunset"][0][-5:]),
                "days": days, "updated": time.strftime("%-I:%M %p")}
    return cached("weather", 900, get)


# ── storage ──────────────────────────────────────────────────────────────
def human(n):
    for u in ("B", "KiB", "MiB", "GiB", "TiB"):
        if n < 1024 or u == "TiB":
            return f"{n:.1f} {u}" if u != "B" else f"{n} B"
        n /= 1024


def storage(refresh=False):
    st = os.statvfs("/nix/store")
    total, free = st.f_blocks * st.f_frsize, st.f_bavail * st.f_frsize
    du_path = os.path.join(CACHE, "store-du.json")
    du = {}
    try:
        with open(du_path) as f:
            du = json.load(f)
    except (OSError, ValueError):
        pass
    running = os.path.exists(du_path + ".lock")
    if (refresh or not du or time.time() - du.get("at", 0) > 6 * 3600) and not running:
        # du of the whole store is slow (minutes): do it in the background, niced.
        subprocess.Popen(["sh", "-c", f'touch "{du_path}.lock"; s=$(nice -n 19 du -sb /nix/store 2>/dev/null | cut -f1); '
                          f'[ -n "$s" ] && printf \'{{"bytes": %s, "at": %s}}\' "$s" "$(date +%s)" > "{du_path}"; rm -f "{du_path}.lock"'],
                         start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        running = True
    gens = sorted(int(m.group(1)) for x in os.listdir("/nix/var/nix/profiles")
                  if (m := re.match(r"system-(\d+)-link$", x)))
    cur = os.readlink("/nix/var/nix/profiles/system")
    curgen = re.match(r"system-(\d+)-link", cur)
    return {"ok": True, "store_bytes": du.get("bytes"), "store": human(du["bytes"]) if du.get("bytes") else None,
            "measured": time.strftime("%a %-I:%M %p", time.localtime(du["at"])) if du.get("at") else None,
            "measuring": running, "disk_total": human(total), "disk_free": human(free),
            "disk_used_pct": round(100 * (1 - free / total)) if total else 0,
            "generations": len(gens), "current_gen": int(curgen.group(1)) if curgen else None,
            "oldest_gen": gens[0] if gens else None,
            "auto_gc": "weekly, --delete-older-than 14d (nix.gc in configuration.nix)"}


# ── updater ──────────────────────────────────────────────────────────────
FLAKE_ROOTS = [HOME + "/Projects", HOME + "/.config", "/etc/nixos", HOME + "/nixos", HOME + "/.dotfiles"]


def find_flakes():
    extra = cfg().get("updater", {}).get("flakes", [])
    out_ = []
    for root in FLAKE_ROOTS:
        if not os.path.isdir(root):
            continue
        for dirpath, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("node_modules", "result", "target", "build", "dist")]
            if dirpath.count(os.sep) - root.count(os.sep) >= 3:
                dirs[:] = []
            if "flake.lock" in files and "flake.nix" in files:
                out_.append(dirpath)
    return sorted(set(out_ + [os.path.expanduser(x) for x in extra]))


def flake_info(path, stale_days):
    try:
        lock = json.load(open(os.path.join(path, "flake.lock")))
    except (OSError, ValueError):
        return None
    nodes = lock.get("nodes", {})
    root_inputs = nodes.get(lock.get("root", "root"), {}).get("inputs", {})
    inputs = []
    for name, ref in root_inputs.items():
        node = nodes.get(ref if isinstance(ref, str) else "", {})
        lk = node.get("locked", {})
        lm = lk.get("lastModified")
        if not lm:
            continue
        age = int((time.time() - lm) / 86400)
        inputs.append({"name": name, "age_days": age, "rev": (lk.get("rev") or "")[:10],
                       "src": lk.get("owner", "") + "/" + lk.get("repo", "") if lk.get("owner") else lk.get("type", ""),
                       "stale": age > stale_days})
    inputs.sort(key=lambda i: -i["age_days"])
    return {"path": path, "name": os.path.basename(path), "inputs": inputs,
            "stale": sum(i["stale"] for i in inputs), "oldest": inputs[0]["age_days"] if inputs else 0}


KERNEL_NIX = "/etc/nixos/r3dg0d-kernel.nix"
NIX_PATH_ENV = "/run/current-system/sw/bin:/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"


def _series(v):
    m = re.match(r"(\d+)\.(\d+)", v or "")
    return (int(m.group(1)), int(m.group(2))) if m else None


def _kernels_org(rev):
    k = json.loads(fetch(f"https://raw.githubusercontent.com/NixOS/nixpkgs/{rev}/pkgs/os-specific/linux/kernel/kernels-org.json")[0])
    return {n: e.get("version") for n, e in k.items() if re.fullmatch(r"\d+\.\d+", n)}


def kernel_check_cache():
    try:
        with open(os.path.join(CACHE, "kernel-check.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def kernel_info(latest_rev):
    running = os.uname().release
    def kver(link):
        m = re.search(r"linux-([\d.]+)", os.readlink(link) if os.path.islink(link) else "")
        return m.group(1) if m else None
    booted, current = kver("/run/booted-system/kernel"), kver("/run/current-system/kernel")
    cur_s = _series(current)
    latest = None
    # nixpkgs at the newest channel revision (what the next channel update brings)
    chan = {}
    if latest_rev:
        try:
            chan = _kernels_org(latest_rev)
            if cur_s and current:
                latest = chan.get("%d.%d" % cur_s)
        except Exception:
            pass
    # nixos-unstable, for series the stable channel has not picked up yet
    unstable = {}
    try:
        urev = fetch("https://channels.nixos.org/nixos-unstable/git-revision")[0].strip()
        unstable = _kernels_org(urev)
    except Exception:
        pass
    # nixpkgs this machine builds from right now (<nixpkgs> = the root channel)
    local = {}
    try:
        expr = ('with import <nixpkgs> {}; builtins.listToAttrs (map (n: { name = n; value = let r = builtins.tryEval pkgs.${n}.kernel.version; '
                'in if r.success then r.value else null; }) (builtins.filter (n: builtins.match "linuxPackages_[0-9]+_[0-9]+" n != null) (builtins.attrNames pkgs)))')
        d = json.loads(subprocess.run(["nix-instantiate", "--eval", "--json", "--strict", "--expr", expr], capture_output=True, text=True,
                                      timeout=60, env={**os.environ, "PATH": NIX_PATH_ENV + ":" + os.environ.get("PATH", "")}).stdout or "{}")
        local = {k[len("linuxPackages_"):].replace("_", "."): v for k, v in d.items() if v}
    except Exception:
        pass
    # kernel.org
    upstream = {}
    try:
        rel = json.loads(fetch("https://www.kernel.org/releases.json")[0])
        for r in rel.get("releases", []):
            if r.get("moniker") in ("mainline", "stable", "longterm") and "rc" not in r["version"]:
                sv = _series(r["version"])
                if sv:
                    upstream["%d.%d" % sv] = r["version"]
        up_latest = (rel.get("latest_stable") or {}).get("version")
    except Exception:
        up_latest = None
    def best(d):
        ks = [(_series(k), k) for k in d if _series(k)]
        return max(ks)[1] if ks else None
    up_series = best({**upstream, **({"%d.%d" % _series(up_latest): up_latest} if _series(up_latest) else {})})
    local_best, chan_best, unst_best = best(local), best(chan), best(unstable)
    nixpkgs_best = best({**local, **chan, **unstable})
    # the series an upgrade would move to: newest in nixpkgs (this system's channel first)
    cand = None
    if cur_s and nixpkgs_best and _series(nixpkgs_best) > cur_s:
        cand = nixpkgs_best
    cand_where = None
    if cand:
        cand_where = "installed channel" if cand in local else ("next channel update" if cand in chan else "nixos-unstable only")
    chk = kernel_check_cache()
    cur_series = "%d.%d" % cur_s if cur_s else None
    return {"running": running, "booted": booted, "current": current, "series": cur_series, "latest": latest,
            "reboot": bool(booted and current and booted != current),
            "update": bool(latest and current and latest != current),
            "upstream_latest": up_series, "upstream_version": upstream.get(up_series) or up_latest,
            "upstream_series_version": upstream.get(cur_series),
            "nixpkgs_local": local_best, "nixpkgs_local_version": local.get(local_best),
            "nixpkgs_channel": chan_best, "nixpkgs_channel_version": chan.get(chan_best),
            "nixpkgs_unstable": unst_best, "nixpkgs_unstable_version": unstable.get(unst_best),
            "candidate": cand, "candidate_version": (local.get(cand) or chan.get(cand) or unstable.get(cand)) if cand else None,
            "candidate_where": cand_where,
            "candidate_unstable_only": bool(cand and cand not in local and cand not in chan),
            "upstream_ahead": bool(up_series and nixpkgs_best and _series(up_series) > _series(nixpkgs_best)),
            "check": chk if chk and chk.get("series") == cand else {}, "last_check": chk,
            "nvidia": _nvidia_version(), "file": KERNEL_NIX, "available": sorted(local, key=_series)}


def _nvidia_version():
    try:
        m = re.search(r'version\s*=\s*"([\d.]+)"', open(KERNEL_NIX).read())
        return m.group(1) if m else None
    except OSError:
        return None


def profile_info():
    try:
        d = json.loads(run(["nix", "profile", "list", "--json"], 20))
        el = d.get("elements", {})
        items = el.items() if isinstance(el, dict) else enumerate(el)
        pkgs = []
        for name, e in items:
            sp = (e.get("storePaths") or [""])[0]
            m = re.match(r"/nix/store/[a-z0-9]+-(.+)", sp)
            pkgs.append({"name": str(name), "version": m.group(1) if m else "", "source": e.get("originalUrl") or e.get("attrPath", "")})
        return pkgs
    except (ValueError, AttributeError):
        return []


def updater_full():
    c = cfg().get("updater", {})
    stale_days = int(c.get("stale_days", 30))
    ver = run(["nixos-version"])
    m = re.match(r"(\d+\.\d+)(?:pre\d+)?\.(\d+)\.([0-9a-f]+)", ver)
    channel = c.get("channel") or (f"nixos-{m.group(1)}" if m and "pre" not in ver else "nixos-unstable")
    cur_build, cur_rev = (int(m.group(2)), m.group(3)) if m else (None, "")
    rel, new_rev, full_rev, commits = "", "", "", None
    try:
        full_rev, final = fetch(f"https://channels.nixos.org/{channel}/git-revision")
        full_rev = full_rev.strip()
        r = re.search(r"/(nixos-[\w.]+)/git-revision$", final)
        rel = r.group(1) if r else ""
        new_rev = full_rev[:12]
    except Exception as e:
        rel = f"check failed: {e}"
    update = bool(new_rev and cur_rev and not new_rev.startswith(cur_rev[:12]))
    if update:
        try:
            commits = json.loads(fetch(f"https://api.github.com/repos/NixOS/nixpkgs/compare/{cur_rev}...{new_rev}")[0]).get("total_commits")
        except Exception:
            pass
    flakes = [f for f in (flake_info(p, stale_days) for p in find_flakes()) if f]
    fw = {"present": bool(shutil.which("fwupdmgr")), "updates": []}
    if fw["present"]:
        try:
            d = json.loads(run(["fwupdmgr", "get-updates", "--json"], 60) or "{}")
            for dev in d.get("Devices", []):
                for rl in dev.get("Releases", []):
                    fw["updates"].append({"device": dev.get("Name"), "version": rl.get("Version")})
        except ValueError:
            pass
    fp = {"present": bool(shutil.which("flatpak")), "user": [], "system": []}
    if fp["present"]:
        for scope in ("user", "system"):
            for l in run(["flatpak", "remote-ls", "--updates", f"--{scope}", "--columns=application,version"], 60).splitlines():
                if l.strip():
                    fp[scope].append(l.split("\t")[0])
    kern = kernel_info(full_rev)
    stale_flakes = sum(1 for f in flakes if f["stale"])
    total = int(update) + stale_flakes + len(fw["updates"]) + len(fp["user"]) + len(fp["system"]) + int(kern["reboot"]) + int(bool(kern.get("candidate")))
    nvd = None
    try:
        nvd = open(os.path.join(CACHE, "nvd.txt")).read()[-6000:]
        nvd_at = time.strftime("%a %-I:%M %p", time.localtime(os.path.getmtime(os.path.join(CACHE, "nvd.txt"))))
    except OSError:
        nvd_at = None
    return {"ok": True, "channel": channel, "current": ver, "current_rev": cur_rev, "latest": rel, "latest_rev": new_rev,
            "update": update, "behind": commits, "commits": commits,
            "last_switch": time.strftime("%a %d %b %-I:%M %p", time.localtime(os.lstat("/nix/var/nix/profiles/system").st_mtime)),
            "flake": os.path.exists("/etc/nixos/flake.nix"), "kernel": kern, "flakes": flakes, "stale_days": stale_days,
            "firmware": fw, "flatpak": fp, "profile": profile_info(), "nvd": nvd, "nvd_at": nvd_at,
            "total": total, "checked": time.strftime("%-I:%M %p")}


def updater():
    return cached("updater", 1800, updater_full)


# ── constructs (vmtools: windowsvm / linuxvm / androidvm) ────────────────
APPLE_RUN = os.path.expanduser("~/src/vmtools/bin/run-tool.py")


def _cli(tool):
    # iosvm/macosvm run from the ~/src/vmtools checkout until the vmtools package is rebuilt
    if shutil.which(tool) or tool not in ("iosvm", "macosvm") or not os.path.exists(APPLE_RUN):
        return [tool]
    return ["python3", APPLE_RUN, tool]


def constructs():
    def vms(tool):
        txt = re.sub(r"\x1b\[[0-9;]*m", "", run(_cli(tool) + ["list"], 20))
        if txt.strip().lower().startswith("no "):
            return [], ""
        if "No VMs defined" in txt or not txt.strip():
            return [], txt.strip()
        rows = []
        for l in txt.splitlines():
            parts = l.split()
            if len(parts) >= 2 and parts[0] not in ("NAME", "Name", "list", "Id") and not l.startswith(("-", "=")):
                rows.append({"name": parts[0], "state": " ".join(parts[1:3])})
        return rows, txt.strip()
    items = []
    meta = [("windowsvm", "Windows Construct", "QEMU/KVM · libvirt", "galaxy-windows"),
            ("linuxvm", "Linux Construct", "QEMU/KVM · libvirt", "galaxy-linux"),
            ("androidvm", "Android Construct", "Docker-Android-Pro", "galaxy-android"),
            ("iosvm", "iOS Construct", "qemu-sptm (darwin-vm) · Simulator via macOS", "galaxy-ios"),
            ("macosvm", "macOS Construct", "QEMU/KVM + OpenCore · Docker-OSX", "galaxy-macos")]
    for tool, name, backend, icon in meta:
        present = bool(shutil.which(tool)) or len(_cli(tool)) > 1
        rows, raw = vms(tool) if present else ([], "")
        note = ""
        if tool == "androidvm" and present:
            st = re.sub(r"\x1b\[[0-9;]*m", "", run([tool, "status"], 15))
            if "NOT CONFIGURED" in st:
                note = "not configured · run androidvm setup (Docker-Android-Pro login)"
        elif "error" in raw.lower():
            note = raw.splitlines()[-1][:120]
        items.append({"tool": tool, "name": name, "backend": backend, "icon": icon, "present": present,
                      "vms": rows, "running": sum(1 for r in rows if "running" in r["state"].lower()), "note": note})
    doctor = re.sub(r"\x1b\[[0-9;]*m", "", run(["vmtools", "doctor"], 40))
    fails = [l.strip()[2:].strip() for l in doctor.splitlines() if l.strip().startswith("✗")]
    return {"ok": True, "items": items, "doctor_fails": sorted(set(fails)), "checked": time.strftime("%-I:%M %p")}


# ── network ──────────────────────────────────────────────────────────────
def nm_fields(line):
    return re.split(r"(?<!\\):", line)


def network():
    devs = []
    for l in run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev"]).splitlines():
        d, t, s, c = (nm_fields(l) + ["", "", "", ""])[:4]
        if t in ("loopback", "wifi-p2p"):
            continue
        devs.append({"device": d, "type": t, "state": s, "connection": c.replace("\\:", ":")})
    wifi_on = run(["nmcli", "radio", "wifi"]) == "enabled"
    nets, seen = [], set()
    if wifi_on:
        for l in run(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "auto"], 15).splitlines():
            u, ssid, sig, sec = (nm_fields(l) + ["", "", "", ""])[:4]
            ssid = ssid.replace("\\:", ":")
            if not ssid or ssid in seen:
                continue
            seen.add(ssid)
            nets.append({"ssid": ssid, "signal": int(sig or 0), "security": sec or "open", "active": u == "*"})
    known = set(nm_fields(l)[0].replace("\\:", ":") for l in run(["nmcli", "-t", "-f", "NAME,TYPE", "con", "show"]).splitlines()
                if l.endswith(":802-11-wireless"))
    for n in nets:
        n["known"] = n["ssid"] in known
    bt_show = run(["bluetoothctl", "show"], 5)
    bt_on = "Powered: yes" in bt_show
    bt = []
    if bt_on:
        connected = set(re.findall(r"Device ([0-9A-F:]{17})", run(["bluetoothctl", "devices", "Connected"], 5)))
        for l in run(["bluetoothctl", "devices", "Paired"], 5).splitlines():
            m = re.match(r"Device ([0-9A-F:]{17}) (.*)", l)
            if m:
                bt.append({"mac": m.group(1), "name": m.group(2), "connected": m.group(1) in connected})
    vpn = next((d for d in devs if d["type"] == "wireguard" and d["state"].startswith("connected")), None)
    primary = next((d for d in devs if d["state"] == "connected" and d["type"] in ("ethernet", "wifi")), None)
    return {"ok": True, "devices": devs, "wifi_on": wifi_on, "networks": nets[:14], "bt_on": bt_on,
            "bt_present": "Controller" in bt_show, "bt_devices": bt, "vpn": vpn["device"] if vpn else None,
            "primary": primary}


def dns():
    servers = []
    try:
        for l in open("/etc/resolv.conf"):
            if l.startswith("nameserver"):
                servers.append(l.split()[1])
    except OSError:
        pass
    tests = []
    for host in ("nixos.org", "github.com", "cache.nixos.org", "example.com"):
        t = time.perf_counter()
        try:
            addr = socket.getaddrinfo(host, 443, proto=socket.IPPROTO_TCP)[0][4][0]
            tests.append({"host": host, "ms": round((time.perf_counter() - t) * 1000), "addr": addr, "ok": True})
        except OSError as e:
            tests.append({"host": host, "ms": None, "addr": str(e), "ok": False})
    mullvad = {}
    try:
        mullvad = json.loads(fetch("https://am.i.mullvad.net/json", 6)[0])
    except Exception:
        pass
    leak = None
    try:  # Mullvad's DNS leak view: which resolvers the outside world sees
        leak = run(["dig", "+short", "TXT", "o-o.myaddr.l.google.com", "@ns1.google.com"], 6).strip('"') or None
    except Exception:
        pass
    return {"ok": all(t["ok"] for t in tests), "servers": servers, "tests": tests,
            "mullvad": bool(mullvad.get("mullvad_exit_ip")), "exit": f'{mullvad.get("city", "?")}, {mullvad.get("country", "?")}' if mullvad else None,
            "public_ip": mullvad.get("ip"), "resolver_seen": leak, "checked": time.strftime("%-I:%M:%S %p")}


def speedtest():
    exe = shutil.which("speedtest-cli")
    cmd = [exe, "--json", "--secure"] if exe else ["nix", "shell", "nixpkgs#speedtest-cli", "-c", "speedtest-cli", "--json", "--secure"]
    raw = run(cmd, 180)
    try:
        d = json.loads(raw)
        res = {"ok": True, "down": round(d["download"] / 1e6, 1), "up": round(d["upload"] / 1e6, 1), "ping": round(d["ping"]),
               "server": f'{d["server"]["sponsor"]} ({d["server"]["name"]})', "via": "speedtest-cli" if exe else "nix shell nixpkgs#speedtest-cli",
               "at": time.strftime("%-I:%M %p")}
    except (ValueError, KeyError):
        res = {"ok": False, "error": "speedtest failed (offline, or nix shell couldn't fetch speedtest-cli)"}
    with open(os.path.join(CACHE, "speedtest.json"), "w") as f:
        json.dump(res, f)
    return res


# ── actions ──────────────────────────────────────────────────────────────
TERM_SCRIPTS = {
    "gc-old": ("Galaxy Storage", "sudo nix-collect-garbage --delete-older-than 14d && nix-collect-garbage --delete-older-than 14d"),
    "gc-all": ("Galaxy Storage", "sudo nix-collect-garbage -d && nix-collect-garbage -d"),
    "optimise": ("Galaxy Storage", "sudo nix-store --optimise"),
    "rebuild": ("Galaxy Updater", "sudo nixos-rebuild switch"),
    "upgrade": ("Galaxy Updater", "sudo nix-channel --update && sudo nixos-rebuild switch"),
    "dry": ("Galaxy Updater", "sudo nix-channel --update && nixos-rebuild dry-build"),
    "diff": ("Galaxy Updater", "CH=$(python3 ~/.config/quickshell/galaxy-hub/hub.py channel); cd \"$(mktemp -d)\" && "
             "sudo nixos-rebuild build -I nixpkgs=https://channels.nixos.org/$CH/nixexprs.tar.xz && "
             "nix run nixpkgs#nvd -- diff /run/current-system ./result | tee ~/.cache/galaxy-hub/nvd.txt"),
    "profile-all": ("Galaxy Updater", "NIXPKGS_ALLOW_UNFREE=1 nix profile upgrade --all --impure"),
    "everything": ("Galaxy Updater", "bash ~/.config/quickshell/galaxy-hub/update-all.sh"),
    "vm-doctor": ("Galaxy Constructs", "vmtools doctor"),
    "android-setup": ("Galaxy Constructs", "androidvm setup"),
}


def term(key, extra=None):
    if key == "flake-update":
        title, script = "Galaxy Updater", "cd " + shlex.quote(extra or "") + " && nix flake update && git --no-pager diff --stat flake.lock"
    elif key == "profile-one":
        title, script = "Galaxy Updater", "NIXPKGS_ALLOW_UNFREE=1 nix profile upgrade --impure " + shlex.quote(extra or "")
    elif key in ("vm-tui", "vm-gui"):
        title, script = "Galaxy Constructs", shlex.quote(extra or "vmtools") + (" tui" if key == "vm-tui" else " gui")
    elif key in ("kernel-upgrade", "kernel-check"):
        if not re.fullmatch(r"\d+\.\d+", extra or ""):
            return out({"ok": False, "msg": "bad kernel series"})
        title = "Galaxy Kernel"
        script = ("bash " + shlex.quote(CFG_DIR + "/kernel-upgrade.sh") + " " + shlex.quote(extra) + (" --check-only" if key == "kernel-check" else ""))
    elif key == "wifi-ask":
        title, script = "Galaxy Network", "nmcli --ask device wifi connect " + shlex.quote(extra or "")
    else:
        title, script = TERM_SCRIPTS[key]
    if key in ("vm-tui",):
        subprocess.Popen(["ghostty", f"--title={title}", "-e", "bash", "-c", script], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return out({"ok": True, "launched": script})
    body = (f"export PATH=/run/wrappers/bin:/run/current-system/sw/bin:$PATH; printf '\\033[38;2;180;107;255m✦ %s\\033[0m\\n\\n' {shlex.quote(script)}; {script}; s=$?; echo; "
            f"[ $s -eq 0 ] && printf '\\033[38;2;125;255;168m✓ done\\033[0m\\n' || printf '\\033[38;2;255;92;138m✗ exit %s\\033[0m\\n' $s; "
            "rm -f ~/.cache/galaxy-hub/store-du.json ~/.cache/galaxy-hub/updater.json; read -rp 'Enter to close…' _")
    subprocess.Popen(["ghostty", f"--title={title}", "-e", "bash", "-c", body], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    out({"ok": True, "launched": script})


def action(args):
    a = args[0]
    if a == "term":
        return term(args[1], args[2] if len(args) > 2 else None)
    if a == "wifi":
        run(["nmcli", "radio", "wifi", args[1]])
    elif a == "wifi-connect":  # known or open networks; secured new ones go through term wifi-ask
        r = subprocess.run(["nmcli", "dev", "wifi", "connect", args[1]], capture_output=True, text=True, timeout=40)
        return out({"ok": r.returncode == 0, "msg": (r.stdout or r.stderr).strip()})
    elif a == "wifi-down":
        run(["nmcli", "con", "down", "id", args[1]], 20)
    elif a == "bt-power":
        run(["bluetoothctl", "power", args[1]], 8)
    elif a in ("bt-connect", "bt-disconnect"):
        run(["bluetoothctl", a.split("-")[1], args[1]], 20)
    elif a == "editor":
        subprocess.Popen(["nm-connection-editor"], start_new_session=True)
    out({"ok": True})


# ── waybar ───────────────────────────────────────────────────────────────
def bar(which):
    if which == "weather":
        w = weather()
        if not w.get("ok"):
            return out({"text": "󰖐 --", "class": "offline", "tooltip": "Weather unavailable"})
        out({"text": f'{w["icon"]}  {w["temp"]}{w["unit"][0]}', "class": "ok",
             "tooltip": f'{w["location"]}\n{w["desc"]}, feels {w["feels"]}{w["unit"]}\n\nClick: weather panel'})
    elif which == "updates":
        u = updater()
        if not u.get("ok"):
            return out({"text": "", "class": "unknown", "tooltip": "Update check failed"})
        n = u.get("total", int(bool(u.get("update"))))
        cls = "available" if n else "current"
        txt = f"󰚰  {n}" if n else ""
        out({"text": txt, "class": cls,
             "tooltip": f'{u["channel"]} · {"update available" if u["update"] else "up to date"}\nrunning {u["current"]}\nlatest  {u["latest"]}\n\nClick: updater · Right-click: storage'})
    elif which == "net":
        n = network()
        p = n["primary"]
        icon = "󰈀" if p and p["type"] == "ethernet" else ("󰤨" if p else "󰤭")
        label = "wired" if p and p["type"] == "ethernet" else (p["connection"] if p else "offline")
        vpn = "  󰦝" if n["vpn"] else ""
        bt = "  󰂯" if n["bt_on"] else ""
        out({"text": f"{icon}  {label}{vpn}{bt}", "class": "vpn" if n["vpn"] else ("up" if p else "down"),
             "tooltip": f'{label}{" · Mullvad " + n["vpn"] if n["vpn"] else ""}\nBluetooth {"on" if n["bt_on"] else "off"}\n\nClick: network panel'})


if __name__ == "__main__":
    import urllib.parse  # noqa
    cmd, rest = (sys.argv[1] if len(sys.argv) > 1 else "help"), sys.argv[2:]
    if cmd == "weather": out(weather())
    elif cmd == "storage": out(storage("--refresh" in rest))
    elif cmd == "updater":
        if "--refresh" in rest:
            try: os.remove(os.path.join(CACHE, "updater.json"))
            except OSError: pass
        out(updater())
    elif cmd == "network": out(network())
    elif cmd == "constructs": out(cached("constructs", 60, constructs) if "--refresh" not in rest else constructs())
    elif cmd == "channel":
        v = run(["nixos-version"]); mm = re.match(r"(\d+\.\d+)", v)
        print(cfg().get("updater", {}).get("channel") or (f"nixos-{mm.group(1)}" if mm and "pre" not in v else "nixos-unstable"))
    elif cmd == "bar-refresh":  # background refresh for waybar
        try: os.remove(os.path.join(CACHE, "updater.json"))
        except OSError: pass
        updater()
    elif cmd == "dns": out(dns())
    elif cmd == "speedtest": out(speedtest())
    elif cmd == "last-speedtest":
        try: out(json.load(open(os.path.join(CACHE, "speedtest.json"))))
        except (OSError, ValueError): out({"ok": False, "error": "no test yet"})
    elif cmd == "action": action(rest)
    elif cmd == "bar": bar(rest[0])
    else: print(__doc__)
