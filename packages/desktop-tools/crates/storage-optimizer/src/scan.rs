//! Storage analysis. Walks the home directory (plus a few known local data
//! roots) once, in parallel, never crossing filesystems, never following
//! symlinks, counting hard-linked files and bind-mounted directories once,
//! and measuring allocated blocks (so sparse VM images are not overstated).
//! Every byte is attributed to exactly one category; big things are recorded
//! as Large Items with a classification and a protection verdict.
//!
//! Results are written to $XDG_CACHE_HOME/storage-optimizer/scan.json (0600,
//! it contains file names) and progress is streamed as JSON lines.

use crate::{common, Config, APP};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

pub const CATEGORIES: &[(&str, &str, &str)] = &[
    ("nix", "Nix", "The Nix store: every system generation, package and build dependency."),
    ("flatpak", "Flatpak", "Flatpak apps and runtimes (user and system) and their app data."),
    ("trash", "Trash", "Files you have moved to the Trash."),
    ("logs", "Logs", "The systemd journal and large log files."),
    ("caches", "Caches", "Application caches under ~/.cache that are not classified elsewhere."),
    ("developer", "Developer files", "Source trees, build outputs, dependency and package caches."),
    ("gaming", "Gaming", "Steam, Proton prefixes, Minecraft, emulators and their data."),
    ("ai-models", "AI Models", "Model weights, datasets and generated outputs (Hugging Face, Ollama, local tools)."),
    ("vms", "Virtual Machines", "VM disk images and VM tool data."),
    ("containers", "Containers", "Docker and Podman images, containers and build cache."),
    ("downloads", "Downloads", "Your Downloads folder."),
    ("videos", "Videos", "Your Videos folder (excluding recordings)."),
    ("recordings", "Recordings", "Screen and game recordings."),
    ("personal", "Personal files", "Documents, Pictures, Music, Desktop and your notes."),
    ("misc", "Miscellaneous", "Everything else in your home directory."),
];

// ------------------------------------------------------------------ rules

#[derive(Clone, Default)]
struct Ctx {
    cat: &'static str,
    protected: Option<String>,
    in_repo: bool,
    /// Inside a recorded Large Item (so its files are not listed separately).
    in_item: bool,
    rebuildable: bool,
    hint: Option<&'static str>,
    tool: Option<&'static str>,
    /// Inside a directory named like "models"/"checkpoints".
    in_models_dir: bool,
}

#[derive(Clone)]
struct Anchor {
    class: &'static str,
    label: Option<String>,
    trashable: bool,
}

struct Rules {
    home: PathBuf,
    xdg: HashMap<&'static str, PathBuf>,
    vaults: Vec<PathBuf>,
    exclude: Vec<PathBuf>,
    threshold: u64,
    cfg: Config,
}

/// Extensions that are model weights wherever they appear.
const MODEL_EXT: &[&str] = &["safetensors", "gguf", "ggml", "ckpt", "pth", "onnx", "tflite", "mlmodel"];
/// Generic extensions (".bin" is anything) that only count as model weights
/// inside AI data or a directory that is evidently about models.
const MODEL_EXT_AMBIGUOUS: &[&str] = &["bin", "pt", "pb", "h5"];

fn is_model_file(ctx: &Ctx, name: &str) -> bool {
    let e = ext_of(name);
    MODEL_EXT.contains(&e.as_str()) || (MODEL_EXT_AMBIGUOUS.contains(&e.as_str()) && (ctx.cat == "ai-models" || ctx.in_models_dir))
}
const VM_EXT: &[&str] = &["qcow2", "qcow", "vdi", "vmdk", "vhd", "vhdx", "qed"];
const VIDEO_EXT: &[&str] = &["mp4", "mkv", "webm", "mov", "avi", "m4v", "flv", "ts"];
const SECRET_DIRS: &[&str] = &[".ssh", ".gnupg", ".password-store", ".local/share/keyrings", ".pki"];
const BROWSER_DIRS: &[&str] = &[
    ".mozilla", ".librewolf", ".zen", ".config/google-chrome", ".config/chromium", ".config/BraveSoftware",
    ".config/vivaldi", ".config/net.imput.helium", ".var/app/org.mozilla.firefox", ".var/app/org.torproject.torbrowser-launcher",
];

fn ext_of(name: &str) -> String {
    name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default()
}

fn xdg_user_dirs(home: &Path) -> HashMap<&'static str, PathBuf> {
    let mut m = HashMap::new();
    let defaults = [
        ("DESKTOP", "Desktop"), ("DOWNLOAD", "Downloads"), ("DOCUMENTS", "Documents"),
        ("MUSIC", "Music"), ("PICTURES", "Pictures"), ("VIDEOS", "Videos"),
    ];
    let text = fs::read_to_string(common::config_dir("").join("user-dirs.dirs")).unwrap_or_default();
    for (key, def) in defaults {
        let var = format!("XDG_{key}_DIR=");
        let val = text
            .lines()
            .find_map(|l| l.trim().strip_prefix(&var).map(|v| v.trim_matches('"').replace("$HOME", &home.to_string_lossy())))
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(def));
        m.insert(key, val);
    }
    m
}

fn obsidian_vaults() -> Vec<PathBuf> {
    common::read_json(&common::config_dir("obsidian").join("obsidian.json"))
        .and_then(|v| v["vaults"].as_object().map(|o| o.values().filter_map(|x| x["path"].as_str().map(PathBuf::from)).collect()))
        .unwrap_or_default()
}

impl Rules {
    fn new(cfg: &Config) -> Rules {
        let home = common::home();
        Rules {
            xdg: xdg_user_dirs(&home),
            vaults: obsidian_vaults(),
            exclude: cfg.scan.exclude.iter().map(PathBuf::from).collect(),
            threshold: (cfg.scan.large_item_threshold_gb.max(0.05) * 1e9) as u64,
            cfg: cfg.clone(),
            home,
        }
    }

    fn rel<'a>(&self, p: &'a Path) -> Option<String> {
        p.strip_prefix(&self.home).ok().map(|r| r.to_string_lossy().into_owned())
    }

    /// Context for a directory, derived from its parent's context, its path,
    /// and marker files among its own entries.
    fn dir_ctx(&self, parent: &Ctx, path: &Path, name: &str, names: &HashSet<String>) -> (Ctx, Option<Anchor>) {
        let mut c = parent.clone();
        let mut anchor: Option<Anchor> = None;
        let rel = self.rel(path);
        let r = rel.as_deref().unwrap_or("");
        let parent_rel = path.parent().and_then(|p| self.rel(p)).unwrap_or_default();

        if ["models", "checkpoints", "weights", "loras", "lora"].contains(&name.to_ascii_lowercase().as_str()) {
            c.in_models_dir = true;
        }
        if names.contains(".git") {
            c.in_repo = true;
            c.protected.get_or_insert_with(|| "Git repository".into());
        }
        for (key, label) in [("DOCUMENTS", "Documents"), ("PICTURES", "Pictures"), ("MUSIC", "Music"), ("DESKTOP", "Desktop")] {
            if self.xdg.get(key).is_some_and(|d| d == path) {
                c.cat = "personal";
                c.protected = Some(format!("Personal files ({label})"));
            }
        }
        if self.vaults.iter().any(|v| v == path) {
            c.cat = "personal";
            c.protected = Some("Obsidian vault".into());
        }
        if self.xdg.get("DOWNLOAD").is_some_and(|d| d == path) {
            c.cat = "downloads";
        }
        if self.xdg.get("VIDEOS").is_some_and(|d| d == path) {
            c.cat = "videos";
            c.protected = Some("Personal files (Videos)".into());
        }
        if parent.cat == "videos" && ["recordings", "obs", "matrixshot", "screen recordings", "clips", "replays"].contains(&name.to_ascii_lowercase().as_str()) {
            c.cat = "recordings";
        }
        if SECRET_DIRS.contains(&r) {
            c.protected = Some("Credentials".into());
        }
        if BROWSER_DIRS.contains(&r) {
            c.protected = Some("Browser profile".into());
        }

        let a = |class: &'static str, trashable: bool| Some(Anchor { class, label: None, trashable });
        match r {
            ".cache" | ".cache/fontconfig" | ".cache/mesa_shader_cache" | ".cache/nvidia" => c.cat = "caches",
            ".cache/thumbnails" => { c.cat = "caches"; c.hint = Some("Safe Clean: regenerated automatically"); anchor = a("Cache", false); }
            ".local/share/Trash" => { c.cat = "trash"; anchor = a("Trash", false); }
            ".local/share/flatpak" => { c.cat = "flatpak"; c.hint = Some("Managed by Flatpak — uninstall apps with flatpak or a store"); c.tool = Some("flatpak"); anchor = a("Application Data", false); }
            ".var" | ".var/app" => c.cat = "flatpak",
            // --- gaming
            ".local/share/Steam" | ".steam" => { c.cat = "gaming"; }
            ".var/app/org.prismlauncher.PrismLauncher" | ".local/share/PrismLauncher" | ".minecraft"
            | ".local/share/ModrinthApp" | ".var/app/com.modrinth.ModrinthApp" => {
                c.cat = "gaming";
                c.protected = Some("Minecraft instances (worlds, saves)".into());
                c.hint = Some("Manage instances in the launcher; worlds and saves live here");
            }
            ".config/rpcs3" | ".local/share/rpcs3" => { c.cat = "gaming"; }
            ".cache/rpcs3" => { c.cat = "gaming"; c.rebuildable = true; c.hint = Some("RPCS3 shader/PPU cache — rebuilt by RPCS3, but first launches get slower"); anchor = a("Cache", false); }
            ".local/share/eden" | ".local/share/yuzu" | ".local/share/citra-emu" | ".local/share/dolphin-emu" | ".config/Ryujinx"
            | ".config/PCSX2" | ".local/share/duckstation" | ".config/ppsspp" | ".local/share/Cemu" | ".local/share/Rocket League"
            | ".var/app/com.hypixel.HytaleLauncher" | ".config/heroic" | ".var/app/com.heroicgameslauncher.hgl" | ".local/share/lutris" => {
                c.cat = "gaming";
                c.protected.get_or_insert_with(|| "Game data and saves".into());
                anchor = a("Game", false);
            }
            ".wine" => { c.cat = "gaming"; c.protected = Some("Wine prefix (may contain saves)".into()); anchor = a("Application Data", false); }
            "Games" => { c.cat = "gaming"; c.protected.get_or_insert_with(|| "Games".into()); }
            // --- AI
            ".cache/huggingface" => {
                c.cat = "ai-models"; c.tool = Some("huggingface");
                c.protected = Some("AI models (managed by Hugging Face)".into());
                c.hint = Some("Remove individual models with `huggingface-cli delete-cache`");
            }
            ".ollama" | ".ollama/models" => { c.cat = "ai-models"; c.tool = Some("ollama"); c.protected = Some("AI models (managed by Ollama)".into()); c.hint = Some("Remove models with `ollama rm <model>`"); if r == ".ollama/models" { anchor = a("Model", false); } }
            ".lmstudio" | ".cache/lm-studio" | ".local/share/ComfyUI" | ".cache/torch" | "ai"
            | ".local/share/ai-media" | ".local/share/ollama-import" | ".local/share/llada-image" | ".local/share/text2video" => {
                c.cat = "ai-models";
                c.protected.get_or_insert_with(|| "AI models and data".into());
            }
            // --- VMs / containers
            ".local/share/libvirt" | ".local/share/gnome-boxes" | "VirtualBox VMs" | "winboat" | ".local/share/iosvm" | ".local/share/macosvm" | ".local/share/legacy-ios-kit" => {
                c.cat = "vms"; c.protected = Some("Virtual machine data".into()); anchor = a("VM", false);
            }
            ".local/pipx" | ".local/share/pipx" => { c.cat = "developer"; c.tool = Some("pipx"); c.hint = Some("pipx-installed applications — remove with `pipx uninstall <app>`"); }
            ".local/share/containers" | ".local/share/docker" => { c.cat = "containers"; c.tool = Some("podman"); c.hint = Some("Manage with podman/docker (system prune)"); anchor = a("Container", false); }
            // --- developer
            ".cargo" | ".rustup" | ".m2" | ".gradle" | "go" | ".android" | ".venvs" | "Projects" | "src" | ".local/share/pnpm" | ".cache/go-build" => {
                c.cat = "developer";
            }
            ".npm" | ".cache/pip" | ".cache/uv" | ".cache/pnpm" | ".cache/yarn" | ".cargo/registry" | ".local/share/uv" => {
                c.cat = "developer"; c.rebuildable = true;
                c.hint = Some("Package download cache — re-downloaded on demand (Safe Clean: package caches)");
                anchor = a("Cache", false);
            }
            _ => {}
        }

        // Steam library internals (any library location).
        if name == "compatdata" && path.parent().is_some_and(|p| p.ends_with("steamapps")) {
            c.cat = "gaming"; c.protected = Some("Proton prefixes contain game saves".into());
            c.hint = Some("Review per game in Steam; never removed automatically");
            anchor = Some(Anchor { class: "Application Data", label: Some("Proton prefixes (Steam compatdata)".into()), trashable: false });
        } else if name == "shadercache" && path.parent().is_some_and(|p| p.ends_with("steamapps")) {
            c.cat = "gaming"; c.rebuildable = true;
            c.hint = Some("Rebuilt by Steam/Proton; games may stutter while recompiling");
            anchor = Some(Anchor { class: "Cache", label: Some("Steam shader caches".into()), trashable: false });
        } else if path.parent().is_some_and(|p| p.ends_with("steamapps/common")) {
            c.cat = "gaming"; c.protected = Some("Installed game".into());
            c.hint = Some("Uninstall through Steam");
            anchor = a("Game", false);
        } else if parent_rel.ends_with("PrismLauncher/instances") || parent_rel.ends_with("PrismLauncher/data/instances") {
            c.protected = Some("Minecraft instance (worlds, saves)".into());
            anchor = a("Game", false);
        } else if parent_rel == ".cache/huggingface/hub" && (name.starts_with("models--") || name.starts_with("datasets--")) {
            let label = name.splitn(2, "--").nth(1).unwrap_or(name).replace("--", "/");
            anchor = Some(Anchor { class: if name.starts_with("datasets--") { "Dataset" } else { "Model" }, label: Some(label), trashable: false });
        } else if parent_rel == ".cache/huggingface/hub" || parent_rel == ".cache/huggingface" && name != "hub" {
            // Shared, content-addressed storage (blobs, xet chunks): one item,
            // not thousands of hash-named files.
            anchor = Some(Anchor { class: "Model", label: Some(format!("Hugging Face shared storage ({name})")), trashable: false });
        } else if ["ai", ".local/share/ai-media", ".local/share/ollama-import", ".local/share/llada-image", ".local/share/text2video"].contains(&parent_rel.as_str()) {
            anchor = a("Model", false); // refined by content below
        } else if parent_rel == ".local/pipx/venvs" || parent_rel == ".local/share/pipx/venvs" {
            anchor = Some(Anchor { class: "Application Data", label: Some(format!("pipx app: {name}")), trashable: false });
        } else if parent_rel == ".var/app" && anchor.is_none() {
            c.cat = if c.cat == "gaming" { "gaming" } else { "flatpak" };
            if c.cat == "flatpak" {
                c.hint = Some("Flatpak app data (settings, saves, caches of that app)");
                anchor = a("Application Data", false);
            } else {
                anchor = a("Game", false);
            }
        } else if parent.cat == "vms" && parent_rel == "winboat" {
            // winboat itself is the anchor
        }

        // Developer build outputs, recognised by markers rather than names
        // alone. Never for a repository root, and never inside tool-managed,
        // AI, gaming, VM or Flatpak data (Hugging Face's hub, for example,
        // carries a CACHEDIR.TAG but holds model weights).
        let marker_ok = !parent.in_item && anchor.is_none() && !names.contains(".git") && c.tool.is_none()
            && !["ai-models", "gaming", "vms", "flatpak", "containers", "personal", "videos", "recordings"].contains(&c.cat)
            && self.cfg.scan.developer;
        if marker_ok {
            let build = |c: &mut Ctx, hint: &'static str| {
                c.cat = "developer";
                c.rebuildable = true;
                c.hint = Some(hint);
                // Gitignored build output inside a repository is not the
                // repository's own content.
                if c.protected.as_deref() == Some("Git repository") { c.protected = None; }
                Some(Anchor { class: "Reproducible Build", label: None, trashable: true })
            };
            if names.contains("pyvenv.cfg") {
                anchor = build(&mut c, "Python virtualenv — recreate with python -m venv / uv venv + install");
            } else if name == "node_modules" {
                anchor = build(&mut c, "Reinstalled by npm/pnpm/yarn install");
            } else if names.contains("CMakeCache.txt") {
                anchor = build(&mut c, "CMake build directory — rebuilt by cmake");
            } else if names.contains("CACHEDIR.TAG") && name == "target" {
                anchor = build(&mut c, "Rust build output — rebuilt by `cargo build`");
            } else if names.contains("CACHEDIR.TAG") {
                c.rebuildable = true;
                c.hint = Some("Marked as a regenerable cache (CACHEDIR.TAG)");
                anchor = Some(Anchor { class: "Cache", label: None, trashable: false });
            }
        }
        if c.in_repo && c.cat == "misc" {
            c.cat = "developer";
        }
        if parent.in_item {
            anchor = None;
        }
        if anchor.is_some() {
            c.in_item = true;
        }
        (c, anchor)
    }

    fn file_cat(&self, ctx: &Ctx, name: &str, bytes: u64) -> &'static str {
        let e = ext_of(name);
        if bytes >= 50_000_000 && is_model_file(ctx, name) && ctx.cat != "gaming" && ctx.cat != "flatpak" && ctx.cat != "vms" {
            return "ai-models";
        }
        if VM_EXT.contains(&e.as_str()) {
            return "vms";
        }
        if ctx.cat == "misc" && e == "log" && bytes >= 10_000_000 {
            return "logs";
        }
        if ctx.cat.is_empty() { "misc" } else { ctx.cat }
    }

    fn file_class(&self, ctx: &Ctx, cat: &str, name: &str) -> &'static str {
        let e = ext_of(name);
        if cat == "ai-models" && is_model_file(ctx, name) { return "Model"; }
        if VM_EXT.contains(&e.as_str()) { return "VM"; }
        if VIDEO_EXT.contains(&e.as_str()) { return "Media"; }
        match cat {
            "gaming" => "Game",
            "developer" if ctx.rebuildable => "Reproducible Build",
            "caches" => "Cache",
            "flatpak" | "containers" => "Application Data",
            _ if ctx.rebuildable => "Cache",
            _ => "Personal",
        }
    }
}

// ------------------------------------------------------------------ walk

#[derive(Default)]
struct Acc {
    cats: HashMap<&'static str, (u64, u64)>, // bytes, files
    items: Vec<Value>,
    unreadable: u64,
}

struct Shared {
    rules: Rules,
    seen_dirs: Mutex<HashSet<(u64, u64)>>,
    seen_links: Mutex<HashSet<(u64, u64)>>,
    files: AtomicU64,
    bytes: AtomicU64,
    area: Mutex<String>,
    ignored: HashSet<String>,
}

#[derive(Default, Clone, Copy)]
struct DirStat {
    bytes: u64,
    files: u64,
    newest: i64,
    model_bytes: u64,
    media_bytes: u64,
}

fn list(acc: &mut Acc, path: &Path) -> Option<Vec<fs::DirEntry>> {
    match fs::read_dir(path) {
        Ok(r) => Some(r.flatten().collect()),
        Err(_) => {
            acc.unreadable += 1;
            None
        }
    }
}

/// Walk a directory whose context is already known (task roots).
fn walk(sh: &Shared, acc: &mut Acc, path: &Path, dev: u64, ctx: &Ctx, depth: usize) -> DirStat {
    match list(acc, path) {
        Some(entries) => walk_entries(sh, acc, entries, dev, ctx, depth),
        None => DirStat::default(),
    }
}

/// Each directory is listed exactly once: its entries both decide its context
/// (marker files such as CACHEDIR.TAG, .git, pyvenv.cfg) and drive the walk.
fn walk_entries(sh: &Shared, acc: &mut Acc, entries: Vec<fs::DirEntry>, dev: u64, ctx: &Ctx, depth: usize) -> DirStat {
    let mut st = DirStat::default();
    if common::cancelled() || depth > 64 {
        return st;
    }
    for e in entries {
        let p = e.path();
        let meta = match fs::symlink_metadata(&p) {
            Ok(m) => m,
            Err(_) => { acc.unreadable += 1; continue; }
        };
        let ft = meta.file_type();
        if ft.is_symlink() {
            continue; // never followed: avoids loops and double counting
        }
        let name = e.file_name().to_string_lossy().into_owned();
        if ft.is_dir() {
            if meta.dev() != dev {
                continue; // filesystem boundary (like du -x)
            }
            if sh.rules.exclude.iter().any(|x| x == &p) {
                continue;
            }
            if !sh.seen_dirs.lock().unwrap().insert((meta.dev(), meta.ino())) {
                continue; // same directory reached twice (bind mount)
            }
            let Some(child) = list(acc, &p) else { continue };
            let child_names: HashSet<String> = child.iter().map(|x| x.file_name().to_string_lossy().into_owned()).collect();
            let (cctx, anchor) = sh.rules.dir_ctx(ctx, &p, &name, &child_names);
            let s = walk_entries(sh, acc, child, dev, &cctx, depth + 1);
            st.bytes += s.bytes;
            st.files += s.files;
            st.newest = st.newest.max(s.newest);
            st.model_bytes += s.model_bytes;
            st.media_bytes += s.media_bytes;
            if let Some(a) = anchor {
                if s.bytes >= sh.rules.threshold {
                    record_item(sh, acc, &p, &cctx, &a, s, "dir");
                }
            }
        } else if ft.is_file() {
            let mut bytes = meta.blocks() * 512;
            if meta.nlink() > 1 && !sh.seen_links.lock().unwrap().insert((meta.dev(), meta.ino())) {
                bytes = 0; // hard link already counted
            }
            let cat = sh.rules.file_cat(ctx, &name, bytes);
            let ent = acc.cats.entry(cat).or_insert((0, 0));
            ent.0 += bytes;
            ent.1 += 1;
            st.bytes += bytes;
            st.files += 1;
            let mt = common::mtime_unix(&meta);
            st.newest = st.newest.max(mt);
            let e = ext_of(&name);
            if is_model_file(ctx, &name) { st.model_bytes += bytes; }
            if VIDEO_EXT.contains(&e.as_str()) { st.media_bytes += bytes; }
            sh.files.fetch_add(1, Ordering::Relaxed);
            sh.bytes.fetch_add(bytes, Ordering::Relaxed);
            if !ctx.in_item && bytes >= sh.rules.threshold {
                let class = sh.rules.file_class(ctx, cat, &name);
                let mut fctx = ctx.clone();
                fctx.cat = cat;
                let a = Anchor { class, label: None, trashable: true };
                record_item(sh, acc, &p, &fctx, &a, DirStat { bytes, files: 1, newest: mt, ..Default::default() }, "file");
            }
        }
    }
    st
}

/// Whether a Large Item may be moved to Trash from the UI.
fn item_trashable(anchor_trashable: bool, protected: bool, tool_managed: bool, kind: &str, class: &str) -> bool {
    anchor_trashable && !protected && !tool_managed && (kind == "file" || class == "Reproducible Build")
}

fn record_item(sh: &Shared, acc: &mut Acc, p: &Path, ctx: &Ctx, a: &Anchor, s: DirStat, kind: &str) {
    let path = p.to_string_lossy().into_owned();
    if sh.ignored.contains(&path) {
        return;
    }
    let mut class = a.class;
    // Tool-managed stores (e.g. Hugging Face blobs) have no file extensions;
    // trust the anchor there and refine only plain directories.
    if class == "Model" && kind == "dir" && ctx.tool.is_none() && s.model_bytes * 2 < s.bytes {
        class = if s.media_bytes * 2 >= s.bytes { "Media" } else { "Application Data" };
    }
    // Deletion is only ever offered for a single ordinary file, or for a
    // recognised reproducible build directory — and never inside protected data.
    let trashable = item_trashable(a.trashable, ctx.protected.is_some(), ctx.tool.is_some(), kind, class);
    acc.items.push(json!({
        "path": path,
        "name": a.label.clone().unwrap_or_else(|| p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()),
        "kind": kind,
        "bytes": s.bytes,
        "files": s.files,
        "category": ctx.cat,
        "classification": class,
        "modified": s.newest,
        "protected": ctx.protected,
        "rebuildable": ctx.rebuildable,
        "inRepo": ctx.in_repo,
        "hint": ctx.hint,
        "trashable": trashable,
    }));
}

// ------------------------------------------------------------------ roots

fn mounts() -> Vec<(String, String)> {
    fs::read_to_string("/proc/self/mounts")
        .unwrap_or_default()
        .lines()
        .filter_map(|l| {
            let f: Vec<&str> = l.split_whitespace().collect();
            (f.len() >= 3).then(|| (f[1].replace("\\040", " "), f[2].to_string()))
        })
        .collect()
}

const NETWORK_FS: &[&str] = &["nfs", "nfs4", "cifs", "smb3", "smbfs", "sshfs", "fuse.sshfs", "davfs", "fuse.davfs2", "9p", "afs", "ceph", "glusterfs", "fuse.rclone", "fuse.s3fs"];
const LOCAL_FS: &[&str] = &["ext4", "ext3", "ext2", "btrfs", "xfs", "f2fs", "zfs", "vfat", "exfat", "ntfs", "ntfs3", "fuseblk", "bcachefs", "jfs", "reiserfs"];

fn fs_type_of(path: &Path, m: &[(String, String)]) -> String {
    let p = path.to_string_lossy();
    m.iter()
        .filter(|(mp, _)| p == mp.as_str() || p.starts_with(&format!("{}/", mp.trim_end_matches('/'))) || mp == "/")
        .max_by_key(|(mp, _)| mp.len())
        .map(|(_, t)| t.clone())
        .unwrap_or_default()
}

/// Local, real filesystems, one entry per underlying filesystem (bind mounts
/// of the same device are reported once).
pub fn filesystems() -> Vec<Value> {
    let mut seen: HashSet<u64> = HashSet::new();
    let mut out = vec![];
    let mut ms = mounts();
    ms.sort_by_key(|(mp, _)| mp.len());
    for (mp, t) in ms {
        if !LOCAL_FS.contains(&t.as_str()) || mp.starts_with("/nix/store") {
            continue;
        }
        let Ok(meta) = fs::metadata(&mp) else { continue };
        if !seen.insert(meta.dev()) {
            continue;
        }
        if let Some((size, used, avail)) = common::statvfs(Path::new(&mp)) {
            if size == 0 { continue; }
            out.push(json!({ "mount": mp, "fstype": t, "size": size, "used": used, "avail": avail,
                             "percent": (used as f64 / size as f64 * 1000.0).round() / 10.0 }));
        }
    }
    out
}

fn steam_libraries(home: &Path) -> Vec<PathBuf> {
    let vdf = home.join(".local/share/Steam/steamapps/libraryfolders.vdf");
    fs::read_to_string(vdf)
        .unwrap_or_default()
        .lines()
        .filter_map(|l| {
            let l = l.trim();
            l.strip_prefix("\"path\"").map(|v| PathBuf::from(v.trim().trim_matches('"')))
        })
        .collect()
}

// ------------------------------------------------------------------ extras

fn nix_store_bytes() -> Option<(u64, u64)> {
    let r = common::run("nix", &["path-info", "--all", "--json", "--json-format", "1"], Duration::from_secs(120));
    let v: Value = serde_json::from_str(&r.stdout).ok()?;
    let o = v.as_object()?;
    Some((o.values().filter_map(|x| x["narSize"].as_u64()).sum(), o.len() as u64))
}

pub fn journal_bytes() -> u64 {
    // "Archived and active journals take up 1G in the file system." is
    // rounded; sum the files instead (readable to wheel/systemd-journal).
    let mut total = 0;
    if let Ok(rd) = fs::read_dir("/var/log/journal") {
        for d in rd.flatten() {
            if let Ok(files) = fs::read_dir(d.path()) {
                for f in files.flatten() {
                    if let Ok(m) = f.metadata() {
                        total += m.blocks() * 512;
                    }
                }
            }
        }
    }
    total
}

fn docker_df() -> Option<Value> {
    if !common::have("docker") {
        return None;
    }
    let r = common::run("docker", &["system", "df", "--format", "{{json .}}"], Duration::from_secs(20));
    if !r.ok {
        return None;
    }
    let rows: Vec<Value> = r.stdout.lines().filter_map(|l| serde_json::from_str(l).ok()).collect();
    Some(json!(rows))
}

/// "4.147GB" / "343.4MB" / "4.096kB" -> bytes (docker's decimal units).
pub fn parse_size(s: &str) -> u64 {
    let s = s.split_whitespace().next().unwrap_or("");
    let idx = s.find(|c: char| c.is_ascii_alphabetic()).unwrap_or(s.len());
    let (num, unit) = s.split_at(idx);
    let n: f64 = num.parse().unwrap_or(0.0);
    let mult = match unit.to_ascii_lowercase().as_str() {
        "b" | "" => 1.0, "kb" | "k" => 1e3, "mb" | "m" => 1e6, "gb" | "g" => 1e9, "tb" | "t" => 1e12,
        "kib" => 1024.0, "mib" => 1048576.0, "gib" => 1073741824.0, "tib" => 1099511627776.0,
        _ => 1.0,
    };
    (n * mult) as u64
}

// ------------------------------------------------------------------ scan

pub fn load_ignored() -> HashSet<String> {
    common::read_json(&crate::ignore_file())
        .and_then(|v| v.as_array().map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect()))
        .unwrap_or_default()
}

pub fn set_ignored(path: &str, ignore: bool) -> i32 {
    let mut s = load_ignored();
    if ignore { s.insert(path.to_string()); } else { s.remove(path); }
    let mut v: Vec<String> = s.into_iter().collect();
    v.sort();
    match common::write_json(&crate::ignore_file(), &v, 0o600) {
        Ok(_) => {
            // Reflect it in the cached scan immediately.
            if let Some(mut scan) = common::read_json(&crate::scan_file()) {
                if let Some(items) = scan["largeItems"].as_array_mut() {
                    for it in items.iter_mut() {
                        if it["path"] == path { it["ignored"] = json!(ignore); }
                    }
                }
                let _ = common::write_json(&crate::scan_file(), &scan, 0o600);
            }
            common::emit(&json!({ "ok": true, "path": path, "ignored": ignore }));
            0
        }
        Err(e) => { common::emit(&json!({ "ok": false, "error": e.to_string() })); 1 }
    }
}

fn progress(phase: &str, sh: &Shared, start: Instant) {
    common::emit(&json!({
        "event": "progress", "phase": phase,
        "files": sh.files.load(Ordering::Relaxed), "bytes": sh.bytes.load(Ordering::Relaxed),
        "area": sh.area.lock().unwrap().clone(), "elapsedMs": start.elapsed().as_millis() as u64,
    }));
}

/// Directories whose children are walked as separate parallel tasks. None of
/// them is itself a Large Item, so no size needs to be aggregated above them.
const SPLIT: &[&str] = &["", ".cache", ".local", ".local/share", ".var", ".var/app", ".config", "Projects", ".cache/huggingface", ".cache/huggingface/hub"];

pub fn run_scan(cfg: &Config) -> Result<Value, String> {
    let start = Instant::now();
    let rules = Rules::new(cfg);
    let home = rules.home.clone();
    let m = mounts();
    let sh = Arc::new(Shared {
        rules,
        seen_dirs: Mutex::new(HashSet::new()),
        seen_links: Mutex::new(HashSet::new()),
        files: AtomicU64::new(0),
        bytes: AtomicU64::new(0),
        area: Mutex::new(String::new()),
        ignored: load_ignored(),
    });
    let mut warnings: Vec<String> = vec![];

    // Roots: home, plus local system data locations relevant to the categories.
    let mut roots: Vec<(PathBuf, Ctx)> = vec![(home.clone(), Ctx { cat: "misc", ..Default::default() })];
    let mut add_root = |p: &str, cat: &'static str, prot: Option<&str>, tool: Option<&'static str>, hint: Option<&'static str>| {
        roots.push((PathBuf::from(p), Ctx { cat, protected: prot.map(String::from), tool, hint, ..Default::default() }));
    };
    add_root("/var/lib/flatpak", "flatpak", None, Some("flatpak"), Some("System Flatpak installation — managed by flatpak"));
    if cfg.scan.ai_models {
        add_root("/var/lib/private/ollama", "ai-models", Some("AI models (managed by Ollama)"), Some("ollama"), Some("Remove models with `ollama rm <model>`"));
    }
    if cfg.scan.vms {
        add_root("/var/lib/libvirt/images", "vms", Some("Virtual machine disks"), None, None);
    }
    if cfg.scan.steam {
        for lib in steam_libraries(&home) {
            if !lib.starts_with(&home) {
                roots.push((lib, Ctx { cat: "gaming", ..Default::default() }));
            }
        }
    }
    for extra in &cfg.scan.extra_roots {
        roots.push((PathBuf::from(extra), Ctx { cat: "misc", ..Default::default() }));
    }

    // Tasks: (path, dev, ctx). Split points fan out into parallel tasks.
    let mut tasks: Vec<(PathBuf, u64, Ctx, Option<Anchor>)> = vec![];
    let mut acc_main = Acc::default();
    for (root, ctx) in roots {
        let t = fs_type_of(&root, &m);
        if NETWORK_FS.contains(&t.as_str()) {
            warnings.push(format!("Skipped network filesystem {}", root.display()));
            continue;
        }
        let Ok(meta) = fs::metadata(&root) else { continue };
        if fs::read_dir(&root).is_err() {
            warnings.push(format!("{} is not readable without root; its size is not included", root.display()));
            continue;
        }
        sh.seen_dirs.lock().unwrap().insert((meta.dev(), meta.ino()));
        let mut stack: Vec<(PathBuf, Ctx)> = vec![(root.clone(), ctx)];
        while let Some((dir, dctx)) = stack.pop() {
            let rel = dir.strip_prefix(&home).map(|r| r.to_string_lossy().into_owned()).ok();
            let split = dir.starts_with(&home) && rel.as_deref().is_some_and(|r| SPLIT.contains(&r));
            if !split {
                tasks.push((dir, meta.dev(), dctx, None));
                continue;
            }
            // Account files directly inside a split dir here; fan out subdirs.
            let Ok(rd) = fs::read_dir(&dir) else { continue };
            for e in rd.flatten() {
                let p = e.path();
                let Ok(md) = fs::symlink_metadata(&p) else { continue };
                if md.file_type().is_symlink() { continue; }
                let name = e.file_name().to_string_lossy().into_owned();
                if md.is_dir() {
                    if md.dev() != meta.dev() || sh.rules.exclude.iter().any(|x| x == &p) { continue; }
                    if !sh.seen_dirs.lock().unwrap().insert((md.dev(), md.ino())) { continue; }
                    let child_names: HashSet<String> = fs::read_dir(&p).map(|r| r.flatten().map(|x| x.file_name().to_string_lossy().into_owned()).collect()).unwrap_or_default();
                    let (cctx, anchor) = sh.rules.dir_ctx(&dctx, &p, &name, &child_names);
                    let crel = p.strip_prefix(&home).map(|r| r.to_string_lossy().into_owned()).unwrap_or_default();
                    if SPLIT.contains(&crel.as_str()) && anchor.is_none() {
                        stack.push((p, cctx));
                    } else {
                        tasks.push((p, md.dev(), cctx, anchor));
                    }
                } else if md.is_file() {
                    let mut bytes = md.blocks() * 512;
                    if md.nlink() > 1 && !sh.seen_links.lock().unwrap().insert((md.dev(), md.ino())) { bytes = 0; }
                    let cat = sh.rules.file_cat(&dctx, &name, bytes);
                    let ent = acc_main.cats.entry(cat).or_insert((0, 0));
                    ent.0 += bytes; ent.1 += 1;
                    sh.files.fetch_add(1, Ordering::Relaxed);
                    sh.bytes.fetch_add(bytes, Ordering::Relaxed);
                    if bytes >= sh.rules.threshold {
                        let class = sh.rules.file_class(&dctx, cat, &name);
                        let mut fctx = dctx.clone(); fctx.cat = cat;
                        record_item(&sh, &mut acc_main, &p, &fctx, &Anchor { class, label: None, trashable: true },
                                    DirStat { bytes, files: 1, newest: common::mtime_unix(&md), ..Default::default() }, "file");
                    }
                }
            }
        }
    }
    // Largest-looking first so the long poles start early.
    tasks.sort_by_key(|(p, ..)| {
        let r = p.to_string_lossy();
        !(r.contains("huggingface") || r.contains("Steam") || r.contains("ai-media") || r.contains(".var/app"))
    });

    // Side jobs that do not walk the filesystem, run concurrently.
    let docker_on = cfg.scan.containers;
    let side = std::thread::spawn(move || {
        let nix = nix_store_bytes();
        let journal = journal_bytes();
        let docker = if docker_on { docker_df() } else { None };
        (nix, journal, docker)
    });
    let cfg2 = cfg.clone();
    let nix_candidates = std::thread::spawn(move || crate::clean::nix_estimates(&cfg2));

    let queue = Arc::new(Mutex::new(tasks));
    let results = Arc::new(Mutex::new(vec![acc_main]));
    let n = cfg.scan.threads.clamp(1, 16);
    let mut handles = vec![];
    for _ in 0..n {
        let q = queue.clone();
        let sh = sh.clone();
        let res = results.clone();
        handles.push(std::thread::spawn(move || {
            let mut acc = Acc::default();
            loop {
                if common::cancelled() { break; }
                let Some((p, dev, ctx, anchor)) = q.lock().unwrap().pop() else { break };
                *sh.area.lock().unwrap() = p.to_string_lossy().replacen(&*sh.rules.home.to_string_lossy(), "~", 1);
                let s = walk(&sh, &mut acc, &p, dev, &ctx, 0);
                if let Some(a) = anchor {
                    if s.bytes >= sh.rules.threshold {
                        record_item(&sh, &mut acc, &p, &ctx, &a, s, "dir");
                    }
                }
            }
            res.lock().unwrap().push(acc);
        }));
    }
    // Tasks were popped from the end; reverse priority accordingly.
    {
        let mut q = queue.lock().unwrap();
        q.reverse();
    }
    let mut last = Instant::now();
    while handles.iter().any(|h| !h.is_finished()) {
        std::thread::sleep(Duration::from_millis(100));
        if last.elapsed() >= Duration::from_millis(300) {
            progress("Scanning files", &sh, start);
            last = Instant::now();
        }
    }
    for h in handles { let _ = h.join(); }
    if common::cancelled() {
        return Err("cancelled".into());
    }
    progress("Measuring Nix store and system data", &sh, start);
    let (nix, journal, docker) = side.join().unwrap_or((None, 0, None));
    progress("Estimating Safe Clean", &sh, start);
    let nix_est = nix_candidates.join().unwrap_or(json!({}));
    if common::cancelled() {
        return Err("cancelled".into());
    }

    // Merge.
    let mut cats: HashMap<&str, (u64, u64)> = HashMap::new();
    let mut items: Vec<Value> = vec![];
    let mut unreadable = 0;
    for a in results.lock().unwrap().drain(..) {
        for (k, (b, f)) in a.cats { let e = cats.entry(k).or_insert((0, 0)); e.0 += b; e.1 += f; }
        items.extend(a.items);
        unreadable += a.unreadable;
    }
    if let Some((b, n)) = nix { cats.insert("nix", (b, n)); }
    let e = cats.entry("logs").or_insert((0, 0)); e.0 += journal;
    let mut docker_total = 0;
    if let Some(d) = &docker {
        for row in d.as_array().into_iter().flatten() {
            docker_total += parse_size(row["Size"].as_str().unwrap_or("0"));
        }
        let e = cats.entry("containers").or_insert((0, 0)); e.0 += docker_total;
    }
    if unreadable > 0 {
        warnings.push(format!("{unreadable} directories or files could not be read and were skipped"));
    }

    items.sort_by(|a, b| b["bytes"].as_u64().cmp(&a["bytes"].as_u64()));
    items.truncate(400);
    for it in items.iter_mut() {
        let ig = it["path"].as_str().is_some_and(|p| sh.ignored.contains(p));
        it["ignored"] = json!(ig);
    }

    let mut cat_list: Vec<Value> = CATEGORIES.iter().map(|(id, label, desc)| {
        let (b, f) = cats.get(id).copied().unwrap_or((0, 0));
        json!({ "id": id, "label": label, "description": desc, "bytes": b, "files": f,
                "measuredBy": match *id { "nix" => "Nix store metadata (NAR size)", "containers" => "home walk + docker system df", "logs" => "journal files + large *.log files", _ => "filesystem walk (allocated blocks)" } })
    }).collect();
    cat_list.sort_by(|a, b| b["bytes"].as_u64().cmp(&a["bytes"].as_u64()));

    let scan_id = format!("{:x}{:x}", common::now_unix(), std::process::id());
    let mut doc = json!({
        "schema": 1,
        "scanId": scan_id,
        "finishedAt": common::now_unix(),
        "durationMs": start.elapsed().as_millis() as u64,
        "filesystems": filesystems(),
        "home": home,
        "categories": cat_list,
        "largeItems": items,
        "thresholdBytes": sh.rules.threshold,
        "docker": docker,
        "warnings": warnings,
    });
    doc["safeClean"] = crate::clean::candidates(cfg, &doc, &nix_est);
    Ok(doc)
}

pub fn scan_main(cfg: &Config, cfg_err: Option<String>) -> i32 {
    let Some(_lock) = common::try_lock(&crate::lock_file()) else {
        common::emit(&json!({ "event": "result", "ok": false, "message": "A scan or cleanup is already running." }));
        return 1;
    };
    common::emit(&json!({ "event": "start" }));
    crate::set_activity("scanning", "Analyzing storage…");
    let outcome = run_scan(cfg);
    crate::set_activity("", "");
    match outcome {
        Ok(mut doc) => {
            if let Some(e) = cfg_err { doc["warnings"].as_array_mut().unwrap().push(json!(e)); }
            if let Err(e) = common::write_json(&crate::scan_file(), &doc, 0o600) {
                common::emit(&json!({ "event": "result", "ok": false, "message": format!("could not save results: {e}") }));
                return 1;
            }
            maybe_notify_models(cfg, &doc);
            let safe = doc["safeClean"]["totalEstimate"].as_u64().unwrap_or(0);
            common::emit(&json!({ "event": "result", "ok": true, "scanId": doc["scanId"], "file": crate::scan_file(),
                "message": format!("Scan finished in {:.1}s — {} safe to clean", doc["durationMs"].as_u64().unwrap_or(0) as f64 / 1000.0, common::human_bytes(safe)) }));
            0
        }
        Err(e) if e == "cancelled" => {
            common::emit(&json!({ "event": "result", "ok": false, "cancelled": true, "message": "Scan cancelled — previous results kept" }));
            130
        }
        Err(e) => {
            common::emit(&json!({ "event": "result", "ok": false, "message": e }));
            1
        }
    }
}

fn maybe_notify_models(cfg: &Config, doc: &Value) {
    if !cfg.notifications.enabled || cfg.notifications.ai_models_over_gb <= 0.0 {
        return;
    }
    let ai = doc["categories"].as_array().and_then(|a| a.iter().find(|c| c["id"] == "ai-models")).and_then(|c| c["bytes"].as_u64()).unwrap_or(0);
    if (ai as f64) < cfg.notifications.ai_models_over_gb * 1e9 {
        return;
    }
    // Once per crossing, not on every scan.
    let state = common::state_dir(APP).join("notified.json");
    let prev = common::read_json(&state).and_then(|v| v["aiModelsGb"].as_u64()).unwrap_or(0);
    let now_gb = ai / 1_000_000_000;
    if prev == 0 || now_gb >= prev + 50 {
        common::notify("Storage Optimizer", "drive-harddisk", &format!("Storage scan found {} of AI models", common::human_bytes(ai)),
                       "Review them under Large Items — models are never removed automatically.");
        let _ = common::write_json(&state, &json!({ "aiModelsGb": now_gb }), 0o600);
    }
}

/// Cheap: filesystem numbers now + the last scan's headline. No walking.
pub fn summary(cfg: &Config, cfg_err: Option<String>) -> Value {
    let home = common::home();
    let fs_list = filesystems();
    let home_fs = common::statvfs(&home).map(|(s, u, a)| json!({ "size": s, "used": u, "avail": a,
        "percent": if s > 0 { (u as f64 / s as f64 * 1000.0).round() / 10.0 } else { 0.0 } }));
    let scan = common::read_json(&crate::scan_file());
    let last = scan.as_ref().map(|s| {
        let largest = s["categories"].as_array().and_then(|a| a.iter().filter(|c| c["id"] != "nix").max_by_key(|c| c["bytes"].as_u64().unwrap_or(0)).cloned());
        json!({
            "finishedAt": s["finishedAt"], "scanId": s["scanId"],
            "safeCleanEstimate": s["safeClean"]["totalEstimate"],
            "safeCleanDefault": s["safeClean"]["defaultEstimate"],
            "largest": largest.map(|c| json!({ "label": c["label"], "bytes": c["bytes"] })),
            "ageHours": (common::now_unix() - s["finishedAt"].as_i64().unwrap_or(0)) / 3600,
        })
    });
    json!({
        "home": home_fs, "filesystems": fs_list, "lastScan": last,
        "lastClean": common::read_json(&common::state_dir(APP).join("last-clean.json")),
        "widget": cfg.widget, "rescanOnOpenAfterHours": cfg.scan.rescan_on_open_after_hours,
        "error": cfg_err,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_size_handles_decimal_and_binary_units() {
        assert_eq!(parse_size("4.147GB"), 4_147_000_000);
        assert_eq!(parse_size("343.4MB"), 343_400_000);
        assert_eq!(parse_size("4.096kB"), 4_096);
        assert_eq!(parse_size("1GiB"), 1_073_741_824);
        assert_eq!(parse_size("512B"), 512);
        assert_eq!(parse_size("0"), 0);
        assert_eq!(parse_size("not-a-size"), 0);
    }

    #[test]
    fn ext_of_lowercases_suffix() {
        assert_eq!(ext_of("model.Safetensors"), "safetensors");
        assert_eq!(ext_of("noext"), "");
        assert_eq!(ext_of("archive.tar.gz"), "gz");
    }

    #[test]
    fn is_model_file_respects_ambiguous_context() {
        let mut ctx = Ctx { cat: "misc", ..Default::default() };
        assert!(is_model_file(&ctx, "weights.safetensors"));
        assert!(is_model_file(&ctx, "llama.gguf"));
        assert!(!is_model_file(&ctx, "payload.bin")); // ambiguous outside AI
        ctx.cat = "ai-models";
        assert!(is_model_file(&ctx, "payload.bin"));
        ctx.cat = "misc";
        ctx.in_models_dir = true;
        assert!(is_model_file(&ctx, "payload.bin"));
    }

    #[test]
    fn item_trashable_safe_vs_protected() {
        assert!(item_trashable(true, false, false, "file", "Personal"));
        assert!(item_trashable(true, false, false, "dir", "Reproducible Build"));
        // directories that are not build outputs are never trashable
        assert!(!item_trashable(true, false, false, "dir", "Model"));
        assert!(!item_trashable(true, true, false, "file", "Personal")); // protected
        assert!(!item_trashable(true, false, true, "file", "Model")); // tool-managed
        assert!(!item_trashable(false, false, false, "file", "Personal")); // anchor says no
    }

    #[test]
    fn file_class_maps_categories() {
        let rules = Rules {
            home: PathBuf::from("/tmp"),
            xdg: Default::default(),
            vaults: vec![],
            exclude: vec![],
            threshold: 1_000_000_000,
            cfg: Config::default(),
        };
        let mut ctx = Ctx { cat: "ai-models", ..Default::default() };
        assert_eq!(rules.file_class(&ctx, "ai-models", "m.gguf"), "Model");
        assert_eq!(rules.file_class(&ctx, "vms", "disk.qcow2"), "VM");
        ctx.rebuildable = true;
        assert_eq!(rules.file_class(&ctx, "developer", "lib.a"), "Reproducible Build");
        assert_eq!(rules.file_class(&ctx, "caches", "x"), "Cache");
        assert_eq!(rules.file_class(&ctx, "gaming", "game.bin"), "Game");
    }
}
