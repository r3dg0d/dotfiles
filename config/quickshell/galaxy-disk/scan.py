#!/usr/bin/env python3
"""galaxy-disk backend.  scan.py scan | status | result | clean PATH | open PATH | copy PATH | cleanable
Scans $HOME (+ a few system dirs) on one filesystem, allocated size (st_blocks), hardlinks counted once.
/nix/store is measured with du -sb (dedupes hardlinks) and nix path-info -S for closures."""
import os, sys, json, time, stat, subprocess, shutil, heapq

HOME = os.path.expanduser("~")
CACHE = os.path.join(HOME, ".cache", "galaxy-disk")
os.makedirs(CACHE, exist_ok=True)
RESULT, PROG, LOCK = (os.path.join(CACHE, f) for f in ("scan.json", "progress.json", "scan.lock"))
ENV = dict(os.environ, PATH="/home/r3dg0d/.nix-profile/bin:/etc/profiles/per-user/r3dg0d/bin:/run/current-system/sw/bin:" + os.environ.get("PATH", ""))
H = lambda p: os.path.join(HOME, p)

CATS = [  # id, name, icon, colour
    ("apps", "Applications", "󰀻", "#b46bff"), ("ai", "AI Models", "󰚩", "#ff6bd5"),
    ("games", "Games", "󰊗", "#7dffa8"), ("vms", "VMs", "󰍹", "#6bd0ff"),
    ("caches", "Caches", "󰃢", "#ffc46b"), ("media", "Media", "󰉍", "#ff8f6b"),
    ("projects", "Projects", "󰲋", "#8fa8ff"), ("other", "Other", "󰉋", "#8a84a8")]
RULES = {  # path -> category (longest prefix wins)
    "apps": [H(".local/share/flatpak"), "/var/lib/flatpak", H(".var/app"), H("Applications"), H(".local/share/unityhub"),
             H("Unity"), H("UnrealEngine"), H(".nix-profile"), H(".local/share/applications"), H(".rustup"),
             H(".local/share/opencode"), H(".npm-global"), H(".zen"), H(".local/share/fonts")],
    "ai": [H(".ollama"), H(".cache/huggingface"), H(".local/share/aivoice"), H(".cache/aivoice"), H("Models"),
           H(".local/share/vllm-venv"), H(".local/share/deepfake"), H(".cache/deepfake"), H(".cache/torch"),
           H(".lhotse"), H("ai-stack-install"), H(".local/share/blurcam"), H(".cache/gdown"), H(".venvs"),
           H(".local/share/fastmcp"), H("blender_mcp"), H(".nv")],
    "games": [H(".local/share/Steam"), H(".local/share/PrismLauncher"), H("ROMS"), H("RetroArch"), H("RPCS3"), H("PCSX2"),
              H("PPSSPP"), H("DuckStation"), H("Dolphin"), H(".local/share/duckstation"), H(".local/share/Rocket League"),
              H(".config/heroic"), H("Games"), H(".local/share/lutris"), H(".local/share/SharpEmu"), H(".ps5upload"),
              H(".cache/Epic"), H(".cache/rpcs3"), H(".var/app/org.DolphinEmu.dolphin-emu"), H(".local/share/com.phantomptr.ps5upload")],
    "vms": [H(".local/share/libvirt"), "/var/lib/libvirt", H(".local/share/vmtools"), H(".cache/vmtools"), H(".cache/galaxy-vm"),
            H(".android"), H(".local/share/docker"), H(".docker"), "/var/lib/docker", H(".local/share/containers"),
            H(".cache/libvirt"), H(".cache/virt-manager")],
    "caches": [H(".cache"), H(".npm"), H(".cargo/registry"), H(".local/share/Trash"), H(".cache/pip"), H(".local/share/uv")],
    "media": [H("Downloads"), H("Movies"), H("Music"), H("Pictures"), H("Videos"), H(".local/share/wallpapers")],
    "projects": [H("src"), H("Projects"), H("projects"), H("code"), H("Development"), H("Unreal Projects"), H("rice-staging"),
                 H("Default Project"), H("Default Project "), H("MatrixRAT"), H("business-forge-validation"), H("terminals")],
}
PREFIX = sorted(((p, c) for c, ps in RULES.items() for p in ps), key=lambda x: -len(x[0]))
EXTRA_ROOTS = ["/var/lib/flatpak", "/var/lib/libvirt", "/var/lib/docker"]
SAFE_CLEAN = [H(p) for p in (".cache/pip", ".cache/uv", ".npm/_cacache", ".cache/thumbnails", ".cache/mesa_shader_cache",
              ".cache/nvidia", ".cache/qtshadercache-x86_64-little_endian-lp64", ".cache/yt-dlp", ".cache/mozilla",
              ".cache/gstreamer-1.0", ".cache/deno", ".cache/claude-cli-nodejs", ".local/share/Trash", ".cache/fontconfig",
              ".cache/go-build", ".cache/electron", ".cache/node-gyp")]


def rule_of(path):
    for p, c in PREFIX:
        if path == p or path.startswith(p + "/"):
            return p, c
    return None, None


def cat_of(path):
    return rule_of(path)[1]


def run(cmd, t=600):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=t, env=ENV).stdout
    except Exception:
        return ""


class Scanner:
    def __init__(self):
        self.seen, self.files, self.bytes, self.cur, self.t0, self.last = set(), 0, 0, "", time.time(), 0
        self.errors = 0
        self.rb = {}  # rule path (or top-level home child for uncategorised) -> exclusive bytes

    def progress(self, phase, force=False):
        now = time.time()
        if force or now - self.last > 0.4:
            self.last = now
            tmp = PROG + ".tmp"
            with open(tmp, "w") as f:
                json.dump({"scanning": True, "phase": phase, "files": self.files, "bytes": self.bytes, "current": self.cur,
                           "elapsed": round(now - self.t0, 1), "pid": os.getpid()}, f)
            os.replace(tmp, PROG)

    def walk(self, path, dev, depth, inherited, irule=None):
        """returns node dict {n,p,s,k,c,f} — children pruned for size"""
        rule, c0 = rule_of(path)
        cat = c0 or inherited
        if rule is None:
            rule = irule if irule else (path if os.path.dirname(path) == HOME else HOME)
        node = {"n": os.path.basename(path) or path, "p": path, "s": 0, "k": cat or "other", "d": True}
        kids, total, nfiles = [], 0, 0
        try:
            it = os.scandir(path)
        except OSError:
            self.errors += 1
            return node
        with it:
            for e in it:
                try:
                    st = e.stat(follow_symlinks=False)
                except OSError:
                    self.errors += 1
                    continue
                if stat.S_ISDIR(st.st_mode):
                    if st.st_dev != dev or e.path in SKIP:
                        continue
                    self.cur = e.path
                    ch = self.walk(e.path, dev, depth + 1, cat, rule)
                    total += ch["s"]
                    nfiles += ch.get("f", 0)
                    kids.append(ch)
                else:
                    if st.st_nlink > 1:
                        key = (st.st_dev, st.st_ino)
                        if key in self.seen:
                            continue
                        self.seen.add(key)
                    sz = st.st_blocks * 512
                    total += sz
                    nfiles += 1
                    self.files += 1
                    self.bytes += sz
                    self.rb[rule] = self.rb.get(rule, 0) + sz
                    if sz > 4 << 20:
                        kids.append({"n": e.name, "p": e.path, "s": sz, "k": cat_of(e.path) or cat or "other"})
                    else:
                        node.setdefault("_small", 0)
                        node["_small"] += sz
                    if (self.files & 0x3FFF) == 0:
                        self.progress("home")
        node["s"], node["f"] = total, nfiles
        small = node.pop("_small", 0)
        # prune: keep children >= 0.5% of this dir or >= 64 MiB, top 60
        keep = [k for k in kids if k["s"] >= max(64 << 20, total * 0.005)] if depth > 0 else [k for k in kids if k["s"] > 0]
        keep = heapq.nlargest(60 if depth else 400, keep, key=lambda k: k["s"])
        rest = total - sum(k["s"] for k in keep)
        if depth > 9:
            keep = []
            rest = total
        if keep and rest > (16 << 20):
            keep.append({"n": "(smaller items)", "p": path, "s": rest, "k": cat or "other", "x": True})
        if keep:
            node["c"] = keep
        return node


SKIP = set()


def human(n):
    for u in ("B", "K", "M", "G", "T"):
        if abs(n) < 1024 or u == "T":
            return f"{n:.1f}{u}" if u not in ("B",) else f"{n}B"
        n /= 1024


def mounts():
    res = []
    seen = set()
    for line in open("/proc/mounts"):
        dev, mp, fs = line.split()[:3]
        if not dev.startswith("/dev/") or dev in seen:
            continue
        seen.add(dev)
        try:
            v = os.statvfs(mp)
        except OSError:
            continue
        tot, free = v.f_blocks * v.f_frsize, v.f_bavail * v.f_frsize
        used = tot - v.f_bfree * v.f_frsize
        res.append({"mount": mp, "dev": dev, "fs": fs, "total": tot, "used": used, "free": free,
                    "pct": round(100 * used / tot, 1) if tot else 0})
    return res


def nix_store(sc):
    sc.cur = "/nix/store (du -sb, dedupes hardlinks)"
    sc.progress("nix", True)
    try:
        du = int(run(["nice", "-n", "15", "du", "-sb", "/nix/store"], 1800).split()[0])
    except Exception:
        du = 0
    items = []
    def closure(label, path):
        o = run(["nix", "path-info", "-S", path], 120).split()
        if len(o) >= 2 and o[-1].isdigit():
            items.append({"n": label, "p": os.path.realpath(path), "s": int(o[-1]), "k": "apps", "closure": True})
    closure("current system closure", "/run/current-system")
    closure("booted system closure", "/run/booted-system")
    for pth, lbl in ((H(".nix-profile"), "user profile closure"), ("/etc/profiles/per-user/r3dg0d", "home packages closure")):
        if os.path.exists(pth):
            closure(lbl, pth)
    gens = sorted(n for n in os.listdir("/nix/var/nix/profiles") if n.startswith("system-") and n.endswith("-link"))
    return {"n": "/nix/store", "p": "/nix/store", "s": du, "k": "apps", "d": True, "c": items, "store": True,
            "gens": len(gens), "note": "du -sb counts hardlinked files once; closures overlap, so they don't add up to the total."}


def scan():
    if os.path.exists(LOCK):
        try:
            os.kill(int(open(LOCK).read()), 0)
            return print(json.dumps({"ok": False, "msg": "scan already running"}))
        except Exception:
            pass
    open(LOCK, "w").write(str(os.getpid()))
    sc = Scanner()
    try:
        sc.progress("home", True)
        dev = os.lstat(HOME).st_dev
        home = sc.walk(HOME, dev, 0, None)
        home["n"] = "~ (home)"
        roots = [home]
        for r in EXTRA_ROOTS:
            if os.path.isdir(r):
                sc.cur = r
                n = sc.walk(r, os.lstat(r).st_dev, 1, None)
                n["n"] = r
                roots.append(n)
        store = nix_store(sc)
        roots.append(store)
        index = {}
        def idx(n):
            if not n.get("x"):
                index.setdefault(n["p"], n)
            for ch in n.get("c", []):
                idx(ch)
        for r in roots:
            idx(r)
        groups = {c[0]: [] for c in CATS}
        for rp, b in sc.rb.items():
            if b <= 0:
                continue
            c = cat_of(rp) or "other"
            nd = index.get(rp)
            name = rp.replace(HOME, "~") if rp != HOME else "~ (loose files)"
            groups[c].append({"n": name, "p": rp, "s": b, "k": c, "d": nd is not None and nd.get("d", False),
                              "full": nd["s"] if nd else b})
        groups["apps"].append(dict(store, n="/nix/store", full=store["s"], c=None) if store["s"] else None)
        groups["apps"] = [g for g in groups["apps"] if g]
        catout = []
        for cid, name, icon, col in CATS:
            items = sorted(groups[cid], key=lambda n: -n["s"])
            size = sum(n["s"] for n in items)
            if size < (1 << 20):
                continue
            catout.append({"id": cid, "name": name, "icon": icon, "color": col, "size": size, "items": items[:80]})
        res = {"ok": True, "scanned_at": time.strftime("%Y-%m-%d %H:%M"), "ts": int(time.time()),
               "duration": round(time.time() - sc.t0, 1), "files": sc.files, "errors": sc.errors,
               "mounts": mounts(), "categories": catout,
               "tree": {"n": "Everything", "p": "/", "s": sum(r["s"] for r in roots), "k": "other", "d": True, "c": roots}}
        tmp = RESULT + ".tmp"
        with open(tmp, "w") as f:
            json.dump(res, f, separators=(",", ":"))
        os.replace(tmp, RESULT)
        shutil.copy(RESULT, os.path.join(CACHE, time.strftime("scan-%Y%m%d-%H%M.json")))
        for old in sorted(x for x in os.listdir(CACHE) if x.startswith("scan-"))[:-5]:
            os.remove(os.path.join(CACHE, old))
    finally:
        with open(PROG, "w") as f:
            json.dump({"scanning": False, "files": sc.files, "elapsed": round(time.time() - sc.t0, 1)}, f)
        os.remove(LOCK)
    print(json.dumps({"ok": True}))


def status():
    try:
        p = json.load(open(PROG))
    except Exception:
        p = {"scanning": False}
    if p.get("scanning"):
        try:
            os.kill(int(open(LOCK).read()), 0)
        except Exception:
            p["scanning"] = False
    p["has_result"] = os.path.exists(RESULT)
    print(json.dumps(p))


def safe(path):
    rp = os.path.realpath(path)
    return any(rp == s or rp.startswith(s + "/") for s in SAFE_CLEAN) and rp != HOME


def main():
    a = sys.argv[1:] or ["status"]
    cmd = a[0]
    if cmd == "scan":
        if "--bg" in a:
            subprocess.Popen([sys.executable, __file__, "scan"], start_new_session=True, stdout=subprocess.DEVNULL,
                             stderr=open(os.path.join(CACHE, "scan.log"), "w"))
            time.sleep(0.3)
            return status()
        return scan()
    if cmd == "status":
        return status()
    if cmd == "result":
        try:
            sys.stdout.write(open(RESULT).read())
        except OSError:
            print('{"ok":false}')
        return
    if cmd == "cleanable":
        out = []
        for s in SAFE_CLEAN:
            if os.path.isdir(s):
                sz = int((run(["du", "-sb", s], 60).split() or ["0"])[0])
                if sz > 1 << 20:
                    out.append({"p": s, "n": s.replace(HOME, "~"), "s": sz})
        return print(json.dumps(sorted(out, key=lambda x: -x["s"])))
    if cmd == "clean":
        p = a[1]
        if not safe(p):
            return print(json.dumps({"ok": False, "msg": "refused: not an allow-listed cache"}))
        rp = os.path.realpath(p)
        before = int((run(["du", "-sb", rp], 120).split() or ["0"])[0])
        for e in os.scandir(rp):  # empty the cache dir, keep the dir itself
            try:
                if e.is_dir(follow_symlinks=False):
                    shutil.rmtree(e.path)
                else:
                    os.unlink(e.path)
            except OSError:
                pass
        after = int((run(["du", "-sb", rp], 120).split() or ["0"])[0])
        return print(json.dumps({"ok": True, "msg": f"freed {human(before - after)} from {rp.replace(HOME, '~')}"}))
    if cmd == "open":
        p = a[1] if os.path.isdir(a[1]) else os.path.dirname(a[1])
        subprocess.Popen(["xdg-open", p], start_new_session=True, env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return print(json.dumps({"ok": True, "msg": "opened " + p.replace(HOME, "~")}))
    if cmd == "copy":
        subprocess.run(["wl-copy", a[1]], env=ENV, timeout=5)
        return print(json.dumps({"ok": True, "msg": "copied " + a[1]}))
    print("usage", file=sys.stderr)


if __name__ == "__main__":
    main()
