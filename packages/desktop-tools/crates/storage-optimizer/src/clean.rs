//! Safe Clean: candidate estimation, exact previews, the confirmed cleanup
//! itself, and "Move to Trash" for one user-selected Large Item.
//!
//! Only these categories can ever be cleaned, and only after the UI has shown
//! the estimate and the user confirmed a selection tied to a specific scan:
//!   nix-generations  old system/user profile generations (never current, booted,
//!                    boot-default or the newest N) — nix-env --delete-generations
//!   nix-garbage      unreachable store paths — nix-store --gc
//!   flatpak-unused   flatpak uninstall --unused (user + system)
//!   trash            gio trash --empty
//!   thumbnails       contents of ~/.cache/thumbnails
//!   journal          journalctl --vacuum-time=<retention>
//!   package-caches   pip/uv/npm/yarn download caches (off by default)
//!   containers       dangling Docker images + build cache (off by default)
//! Everything else is analysis only.

use crate::{common, scan, Config, APP};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

// ------------------------------------------------------------------ measuring

/// Allocated bytes under a path (no symlinks, one filesystem).
pub fn du(path: &Path) -> (u64, u64) {
    fn go(p: &Path, dev: u64, acc: &mut (u64, u64), depth: usize) {
        let Ok(rd) = fs::read_dir(p) else { return };
        for e in rd.flatten() {
            let Ok(m) = fs::symlink_metadata(e.path()) else { continue };
            if m.file_type().is_symlink() || m.dev() != dev { continue; }
            if m.is_dir() {
                if depth < 64 { go(&e.path(), dev, acc, depth + 1); }
            } else {
                acc.0 += m.blocks() * 512;
                acc.1 += 1;
            }
        }
    }
    let mut acc = (0, 0);
    if let Ok(m) = fs::metadata(path) {
        go(path, m.dev(), &mut acc, 0);
    }
    acc
}

fn trash_dirs() -> Vec<PathBuf> {
    let mut v = vec![common::data_home().join("Trash")];
    let uid = common::uid();
    for f in scan::filesystems() {
        if let Some(mp) = f["mount"].as_str() {
            for cand in [format!("{mp}/.Trash-{uid}"), format!("{mp}/.Trash/{uid}")] {
                let p = PathBuf::from(cand);
                if p.is_dir() && !v.contains(&p) { v.push(p); }
            }
        }
    }
    v
}

fn thumbnails_dir() -> PathBuf {
    common::cache_dir("thumbnails")
}

fn package_cache_dirs() -> Vec<(&'static str, PathBuf)> {
    let h = common::home();
    vec![
        ("pip", common::cache_dir("pip")),
        ("uv", common::cache_dir("uv")),
        ("npm", h.join(".npm/_cacache")),
        ("yarn", common::cache_dir("yarn")),
        ("pnpm", common::cache_dir("pnpm")),
    ]
    .into_iter()
    .filter(|(_, p)| p.is_dir())
    .collect()
}

/// "4weeks", "2w", "1month", "30d", "12h" -> seconds (journalctl syntax subset).
pub fn parse_retention(s: &str) -> Option<i64> {
    let s = s.trim();
    let idx = s.find(|c: char| !c.is_ascii_digit())?;
    let (n, unit) = s.split_at(idx);
    let n: i64 = n.parse().ok()?;
    let mult = match unit {
        "s" | "sec" => 1,
        "min" | "m" => 60,
        "h" | "hour" | "hours" => 3600,
        "d" | "day" | "days" => 86400,
        "w" | "week" | "weeks" => 7 * 86400,
        "month" | "months" | "M" => 30 * 86400,
        "y" | "year" | "years" => 365 * 86400,
        _ => return None,
    };
    (n > 0).then_some(n * mult)
}

fn journal_candidates(retention: &str) -> (u64, Vec<String>) {
    let Some(secs) = parse_retention(retention) else { return (0, vec![]) };
    let cutoff = common::now_unix() - secs;
    let mut bytes = 0;
    let mut files = vec![];
    if let Ok(rd) = fs::read_dir("/var/log/journal") {
        for d in rd.flatten() {
            if let Ok(fl) = fs::read_dir(d.path()) {
                for f in fl.flatten() {
                    let name = f.file_name().to_string_lossy().into_owned();
                    // Only archived files (name@seqnum...) are removed by vacuuming.
                    if !name.contains('@') || !name.ends_with(".journal") && !name.ends_with(".journal~") { continue; }
                    if let Ok(m) = f.metadata() {
                        if common::mtime_unix(&m) < cutoff {
                            bytes += m.blocks() * 512;
                            files.push(name);
                        }
                    }
                }
            }
        }
    }
    (bytes, files)
}

fn flatpak_unused(scope: &str) -> Vec<String> {
    if !common::have("flatpak") { return vec![]; }
    // Flatpak lists what --unused would remove, then asks; answering "n" makes
    // this a read-only preview using Flatpak's own dependency logic.
    let r = common::run_with_stdin("flatpak", &["uninstall", "--unused", &format!("--{scope}")], Some("n\n"), Duration::from_secs(60));
    let text = format!("{}\n{}", r.stdout, r.stderr);
    text.lines()
        .filter_map(|l| {
            let f: Vec<&str> = l.split_whitespace().collect();
            // Table rows look like: " 1. [-] org.gnome.Platform  49  flathub  user"
            if f.len() >= 3 && f[0].trim_end_matches('.').parse::<u32>().is_ok() {
                f.iter().find(|x| x.contains('.') && !x.ends_with('.') && x.chars().next().is_some_and(|c| c.is_ascii_alphabetic())).map(|s| {
                    let branch = f.iter().skip_while(|x| *x != s).nth(1).copied().unwrap_or("");
                    format!("{s}//{branch}")
                })
            } else {
                None
            }
        })
        .collect()
}

fn flatpak_sizes(scope: &str) -> HashMap<String, u64> {
    let r = common::run("flatpak", &["list", &format!("--{scope}"), "--columns=application,branch,size"], Duration::from_secs(30));
    r.stdout
        .lines()
        .filter_map(|l| {
            let f: Vec<&str> = l.split('\t').collect();
            (f.len() >= 3).then(|| (format!("{}//{}", f[0].trim(), f[1].trim()), scan::parse_size(&f[2].replace(' ', "").replace('\u{a0}', ""))))
        })
        .collect()
}

// ------------------------------------------------------------------ nix

struct Gen {
    n: u64,
    link: PathBuf,
    target: String,
    date: i64,
}

fn generations(profile_dir: &Path, prefix: &str) -> Vec<Gen> {
    let mut v: Vec<Gen> = fs::read_dir(profile_dir)
        .map(|rd| {
            rd.flatten()
                .filter_map(|e| {
                    let name = e.file_name().to_string_lossy().into_owned();
                    let n: u64 = name.strip_prefix(&format!("{prefix}-"))?.strip_suffix("-link")?.parse().ok()?;
                    let target = fs::read_link(e.path()).ok()?.to_string_lossy().into_owned();
                    let date = fs::symlink_metadata(e.path()).map(|m| common::mtime_unix(&m)).unwrap_or(0);
                    Some(Gen { n, link: e.path(), target, date })
                })
                .collect()
        })
        .unwrap_or_default();
    v.sort_by_key(|g| std::cmp::Reverse(g.n));
    v
}

fn canon(p: &str) -> String {
    fs::canonicalize(p).map(|x| x.to_string_lossy().into_owned()).unwrap_or_default()
}

/// Why a generation (newest-first index `i`) must be kept, if any.
fn generation_keep_reason(i: usize, keep: usize, is_current: bool, is_booted: bool, is_boot_default: bool) -> Option<&'static str> {
    if is_current {
        Some("current")
    } else if is_booted {
        Some("booted")
    } else if is_boot_default {
        Some("boot default")
    } else if i < keep.max(1) {
        Some("recent (kept)")
    } else {
        None
    }
}

/// Which system generations may be deleted: never the current, booted or
/// boot-default one, and never the newest `keep`.
pub fn deletable_system_generations(keep: usize) -> (Vec<u64>, Vec<Value>) {
    let gens = generations(Path::new("/nix/var/nix/profiles"), "system");
    let current = canon("/run/current-system");
    let booted = canon("/run/booted-system");
    let default = canon("/nix/var/nix/profiles/system");
    let mut del = vec![];
    let mut listing = vec![];
    for (i, g) in gens.iter().enumerate() {
        let reason = generation_keep_reason(i, keep, g.target == current, g.target == booted, g.target == default);
        if reason.is_none() { del.push(g.n); }
        listing.push(json!({ "generation": g.n, "date": g.date, "keep": reason.is_some(), "reason": reason }));
    }
    (del, listing)
}

fn user_profile_dir() -> PathBuf {
    common::state_dir("nix").join("profiles")
}

fn deletable_user_generations(keep: usize) -> (Vec<u64>, Vec<Value>) {
    let gens = generations(&user_profile_dir(), "profile");
    let current = fs::read_link(user_profile_dir().join("profile")).map(|p| p.to_string_lossy().into_owned()).unwrap_or_default();
    let mut del = vec![];
    let mut listing = vec![];
    for (i, g) in gens.iter().enumerate() {
        let name = g.link.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let reason = generation_keep_reason(i, keep, name == current, false, false);
        if reason.is_none() { del.push(g.n); }
        listing.push(json!({ "generation": g.n, "date": g.date, "keep": reason.is_some(), "reason": reason }));
    }
    (del, listing)
}

fn store_top(p: &str) -> Option<String> {
    let rest = p.strip_prefix("/nix/store/")?;
    let name = rest.split('/').next()?;
    Some(format!("/nix/store/{name}"))
}

fn nar_sizes(paths: &[String], recursive: bool) -> HashMap<String, u64> {
    let mut out = HashMap::new();
    for chunk in paths.chunks(500) {
        let mut a: Vec<&str> = vec!["path-info", "--json", "--json-format", "1"];
        if recursive { a.push("-r"); }
        a.extend(chunk.iter().map(String::as_str));
        let r = common::run("nix", &a, Duration::from_secs(180));
        if let Ok(Value::Object(o)) = serde_json::from_str::<Value>(&r.stdout) {
            for (k, v) in o {
                if let Some(n) = v["narSize"].as_u64() { out.insert(k, n); }
            }
        }
    }
    out
}

fn closure(paths: &[String]) -> HashSet<String> {
    let mut out = HashSet::new();
    for chunk in paths.chunks(300) {
        let mut a: Vec<&str> = vec!["-qR"];
        a.extend(chunk.iter().map(String::as_str));
        let r = common::run("nix-store", &a, Duration::from_secs(180));
        if r.ok {
            out.extend(r.stdout.lines().map(String::from));
        } else {
            // One bad root should not hide the rest: fall back per path.
            for p in chunk {
                let r = common::run("nix-store", &["-qR", p], Duration::from_secs(60));
                out.extend(r.stdout.lines().map(String::from));
            }
        }
    }
    out
}

/// Estimates for the two Nix categories. Read-only (queries the daemon).
pub fn nix_estimates(cfg: &Config) -> Value {
    if !common::have("nix-store") {
        return json!({ "error": "nix-store not found" });
    }
    let (sys_del, sys_list) = deletable_system_generations(cfg.clean.keep_system_generations);
    let (usr_del, usr_list) = deletable_user_generations(cfg.clean.keep_user_generations);

    // Already unreachable.
    let dead = common::run("nix-store", &["--gc", "--print-dead"], Duration::from_secs(300));
    let dead_paths: Vec<String> = dead.stdout.lines().filter(|l| l.starts_with("/nix/store/")).map(String::from).collect();
    let dead_set: HashSet<String> = dead_paths.iter().cloned().collect();
    let dead_bytes: u64 = nar_sizes(&dead_paths, false).values().sum();

    // Newly unreachable after deleting generations = closure(deleted) minus
    // closure(every other GC root), including roots neo cannot name.
    let sys_targets: Vec<String> = generations(Path::new("/nix/var/nix/profiles"), "system").into_iter()
        .filter(|g| sys_del.contains(&g.n)).map(|g| g.target).collect();
    let usr_targets: Vec<String> = generations(&user_profile_dir(), "profile").into_iter()
        .filter(|g| usr_del.contains(&g.n)).map(|g| canon(&g.link.to_string_lossy())).collect();
    let del_targets: Vec<String> = sys_targets.iter().chain(usr_targets.iter()).cloned().collect();
    let mut gen_bytes = 0;
    let mut roots_err = None;
    if !del_targets.is_empty() {
        let roots = common::run("nix-store", &["--gc", "--print-roots"], Duration::from_secs(120));
        if !roots.ok { roots_err = Some(roots.stderr.trim().to_string()); }
        let mut counts: HashMap<String, i64> = HashMap::new();
        for l in roots.stdout.lines() {
            if let Some((_, t)) = l.rsplit_once(" -> ") {
                if let Some(top) = store_top(t.trim()) { *counts.entry(top).or_default() += 1; }
            }
        }
        for t in &del_targets {
            if let Some(c) = counts.get_mut(t) { *c -= 1; }
        }
        let kept: Vec<String> = counts.into_iter().filter(|(p, c)| *c > 0 && Path::new(p).exists()).map(|(p, _)| p).collect();
        let kept_closure = closure(&kept);
        let del_sizes = nar_sizes(&del_targets, true);
        gen_bytes = del_sizes.iter().filter(|(p, _)| !kept_closure.contains(*p) && !dead_set.contains(*p)).map(|(_, s)| s).sum();
    }
    json!({
        "system": { "deletable": sys_del, "generations": sys_list, "keep": cfg.clean.keep_system_generations },
        "user": { "deletable": usr_del, "generations": usr_list, "profile": user_profile_dir().join("profile"), "keep": cfg.clean.keep_user_generations },
        "generationsBytes": gen_bytes,
        "deadBytes": dead_bytes,
        "deadPaths": dead_paths.len(),
        "rootsError": roots_err,
    })
}

// ------------------------------------------------------------------ candidates

pub fn candidates(cfg: &Config, doc: &Value, nix: &Value) -> Value {
    let d = &cfg.clean.defaults;
    let mut items = vec![];
    let sys_del = nix["system"]["deletable"].as_array().map(|a| a.len()).unwrap_or(0);
    let usr_del = nix["user"]["deletable"].as_array().map(|a| a.len()).unwrap_or(0);
    items.push(json!({
        "id": "nix-generations", "label": "Old NixOS generations",
        "estimate": nix["generationsBytes"], "estimateKind": "estimate",
        "available": sys_del + usr_del > 0, "default": d.nix_generations, "requiresAuth": true,
        "description": format!("Delete {sys_del} old system generation(s) and {usr_del} old user-profile generation(s), then garbage-collect. The current, booted and boot-default generations and the newest {} are always kept. Boot menu entries for deleted generations are removed.", cfg.clean.keep_system_generations),
        "details": nix["system"]["generations"], "userDetails": nix["user"]["generations"],
        "measuredBy": "NAR size of store paths only reachable from these generations (other GC roots subtracted)",
    }));
    items.push(json!({
        "id": "nix-garbage", "label": "Unreachable Nix store paths",
        "estimate": nix["deadBytes"], "estimateKind": "estimate",
        "available": nix["deadBytes"].as_u64().unwrap_or(0) > 0, "default": d.nix_garbage, "requiresAuth": true,
        "description": format!("{} store paths no GC root references (old builds, superseded packages). Removed with nix-store --gc.", nix["deadPaths"]),
        "measuredBy": "NAR size from nix-store --gc --print-dead",
    }));
    let fu = flatpak_unused("user");
    let fs_ = flatpak_unused("system");
    let su = flatpak_sizes("user");
    let ss = flatpak_sizes("system");
    let fbytes: u64 = fu.iter().filter_map(|r| su.get(r)).sum::<u64>() + fs_.iter().filter_map(|r| ss.get(r)).sum::<u64>();
    items.push(json!({
        "id": "flatpak-unused", "label": "Unused Flatpak runtimes",
        "estimate": fbytes, "estimateKind": "estimate",
        "available": !fu.is_empty() || !fs_.is_empty(), "default": d.flatpak_unused, "requiresAuth": !fs_.is_empty(),
        "description": "Runtimes and extensions no installed app uses, as reported by flatpak uninstall --unused.",
        "details": { "user": fu, "system": fs_ },
        "measuredBy": "installed size reported by flatpak list",
    }));
    let mut tb = 0; let mut tf = 0;
    for t in trash_dirs() { let (b, f) = du(&t); tb += b; tf += f; }
    items.push(json!({
        "id": "trash", "label": "Trash",
        "estimate": tb, "estimateKind": "measured",
        "available": tb > 0, "default": d.trash, "requiresAuth": false,
        "description": format!("Permanently delete the {tf} file(s) you already moved to the Trash. Review the Trash first if unsure."),
    }));
    let (thb, thf) = du(&thumbnails_dir());
    items.push(json!({
        "id": "thumbnails", "label": "Thumbnail cache",
        "estimate": thb, "estimateKind": "measured",
        "available": thb > 0, "default": d.thumbnails, "requiresAuth": false,
        "description": format!("{thf} cached image thumbnails. File managers regenerate them on demand."),
    }));
    let (jb, jf) = journal_candidates(&cfg.clean.journal_retention);
    items.push(json!({
        "id": "journal", "label": "Old journal logs",
        "estimate": jb, "estimateKind": "measured",
        "available": jb > 0, "default": d.journal, "requiresAuth": true,
        "description": format!("{} archived journal file(s) older than {} (journalctl --vacuum-time={}). The active journal is kept.", jf.len(), cfg.clean.journal_retention, cfg.clean.journal_retention),
    }));
    let mut pb = 0; let mut pd = vec![];
    for (name, p) in package_cache_dirs() { let (b, _) = du(&p); pb += b; pd.push(json!({ "tool": name, "path": p, "bytes": b })); }
    items.push(json!({
        "id": "package-caches", "label": "Package download caches",
        "estimate": pb, "estimateKind": "measured",
        "available": pb > 0, "default": d.package_caches, "requiresAuth": false,
        "description": "pip / uv / npm / yarn / pnpm download caches. Safe to remove, but packages are re-downloaded next time you install them (slower offline builds).",
        "details": pd,
    }));
    if cfg.scan.containers {
        let (cb, cdet) = docker_candidates(doc);
        items.push(json!({
            "id": "containers", "label": "Docker dangling images & build cache",
            "estimate": cb, "estimateKind": "estimate",
            "available": cb > 0, "default": d.containers, "requiresAuth": false,
            "description": "docker image prune (dangling/untagged images only) and docker builder prune. Tagged images, containers and volumes are not touched.",
            "details": cdet, "measuredBy": "docker's own size reporting",
        }));
    }
    let total: u64 = items.iter().filter(|i| i["available"] == true).filter_map(|i| i["estimate"].as_u64()).sum();
    let def: u64 = items.iter().filter(|i| i["available"] == true && i["default"] == true).filter_map(|i| i["estimate"].as_u64()).sum();
    json!({ "items": items, "totalEstimate": total, "defaultEstimate": def })
}

fn docker_candidates(doc: &Value) -> (u64, Value) {
    if !common::have("docker") { return (0, json!([])); }
    let mut bytes = 0;
    let dangling = common::run("docker", &["images", "-f", "dangling=true", "--format", "{{.ID}}\t{{.Size}}\t{{.CreatedSince}}"], Duration::from_secs(20));
    let imgs: Vec<Value> = dangling.stdout.lines().filter_map(|l| {
        let f: Vec<&str> = l.split('\t').collect();
        (f.len() >= 2).then(|| { let b = scan::parse_size(f[1]); bytes += b; json!({ "image": f[0], "bytes": b, "created": f.get(2) }) })
    }).collect();
    let cache = doc["docker"].as_array().and_then(|a| a.iter().find(|r| r["Type"] == "Build Cache").cloned());
    let cache_bytes = cache.as_ref().map(|c| scan::parse_size(c["Reclaimable"].as_str().unwrap_or("0"))).unwrap_or(0);
    bytes += cache_bytes;
    (bytes, json!({ "danglingImages": imgs, "buildCacheReclaimable": cache_bytes }))
}

pub fn preview(cfg: &Config, cat: &str) -> Value {
    match cat {
        "nix-generations" | "nix-garbage" => nix_estimates(cfg),
        "flatpak-unused" => json!({ "user": flatpak_unused("user"), "system": flatpak_unused("system") }),
        "trash" => json!({ "dirs": trash_dirs().iter().map(|d| { let (b, f) = du(d); json!({ "path": d, "bytes": b, "files": f }) }).collect::<Vec<_>>() }),
        "thumbnails" => { let (b, f) = du(&thumbnails_dir()); json!({ "path": thumbnails_dir(), "bytes": b, "files": f }) }
        "journal" => { let (b, f) = journal_candidates(&cfg.clean.journal_retention); json!({ "bytes": b, "files": f, "retention": cfg.clean.journal_retention }) }
        "package-caches" => json!(package_cache_dirs().iter().map(|(n, p)| json!({ "tool": n, "path": p, "bytes": du(p).0 })).collect::<Vec<_>>()),
        "containers" => docker_candidates(&common::read_json(&crate::scan_file()).unwrap_or(Value::Null)).1,
        _ => json!({ "error": "unknown category" }),
    }
}

// ------------------------------------------------------------------ cleaning

fn log(l: &str) {
    common::emit(&json!({ "event": "log", "line": l }));
}

fn stream_cmd(program: &str, args: &[&str], sink: &mut dyn FnMut(&str)) -> bool {
    use std::io::{BufRead, BufReader};
    use std::process::{Command, Stdio};
    sink(&format!("$ {program} {}", args.join(" ")));
    let Ok(mut child) = Command::new(program).args(args).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn() else {
        sink(&format!("failed to start {program}"));
        return false;
    };
    let err = child.stderr.take().unwrap();
    let (tx, rx) = std::sync::mpsc::channel::<String>();
    let tx2 = tx.clone();
    let so = child.stdout.take().unwrap();
    let h1 = std::thread::spawn(move || { for l in BufReader::new(so).lines().map_while(Result::ok) { let _ = tx.send(l); } });
    let h2 = std::thread::spawn(move || { for l in BufReader::new(err).lines().map_while(Result::ok) { let _ = tx2.send(l); } });
    for l in rx { sink(&l); }
    let _ = h1.join();
    let _ = h2.join();
    child.wait().map(|s| s.success()).unwrap_or(false)
}

fn empty_dir_contents(dir: &Path) -> std::io::Result<()> {
    for e in fs::read_dir(dir)?.flatten() {
        let p = e.path();
        let m = fs::symlink_metadata(&p)?;
        if m.is_dir() { fs::remove_dir_all(&p)?; } else { fs::remove_file(&p)?; }
    }
    Ok(())
}

/// Direct size of what a category removes, where that can be measured.
fn measure_category(id: &str) -> Option<u64> {
    match id {
        "trash" => Some(trash_dirs().iter().map(|d| du(d).0).sum()),
        "thumbnails" => Some(du(&thumbnails_dir()).0),
        "package-caches" => Some(package_cache_dirs().iter().map(|(_, p)| du(p).0).sum()),
        "journal" => Some(scan::journal_bytes()),
        _ => None,
    }
}

fn wait_trash_drained() {
    for _ in 0..240 {
        let busy = trash_dirs().iter().any(|d| {
            ["files", "expunged"].iter().any(|sub| fs::read_dir(d.join(sub)).map(|mut r| r.next().is_some()).unwrap_or(false))
        });
        if !busy { return; }
        std::thread::sleep(Duration::from_millis(250));
    }
    log("Trash is still being emptied in the background; the measurement may be low.");
}

fn free_bytes() -> u64 {
    // Sum of available space over distinct local filesystems.
    scan::filesystems().iter().filter_map(|f| f["avail"].as_u64()).sum()
}

pub fn clean_main(cfg: &Config, args: &[String]) -> i32 {
    let get = |k: &str| args.iter().position(|a| a == k).and_then(|i| args.get(i + 1)).cloned();
    let (Some(scan_id), Some(cats)) = (get("--scan"), get("--categories")) else {
        common::emit(&json!({ "event": "result", "ok": false, "message": "clean needs --scan <id> --categories a,b" }));
        return 2;
    };
    let Some(_lock) = common::try_lock(&crate::lock_file()) else {
        common::emit(&json!({ "event": "result", "ok": false, "message": "A scan or cleanup is already running." }));
        return 1;
    };
    let Some(doc) = common::read_json(&crate::scan_file()) else {
        common::emit(&json!({ "event": "result", "ok": false, "message": "No scan results — analyze first." }));
        return 1;
    };
    // The confirmation must refer to the scan the user actually reviewed.
    if doc["scanId"].as_str() != Some(scan_id.as_str()) {
        common::emit(&json!({ "event": "result", "ok": false, "message": "The scan changed since you reviewed it. Review the new estimate and confirm again." }));
        return 1;
    }
    let selected: Vec<String> = cats.split(',').filter(|s| !s.is_empty()).map(String::from).collect();
    let available: HashMap<String, Value> = doc["safeClean"]["items"].as_array().into_iter().flatten()
        .filter(|i| i["available"] == true).filter_map(|i| Some((i["id"].as_str()?.to_string(), i.clone()))).collect();
    for s in &selected {
        if !available.contains_key(s) {
            common::emit(&json!({ "event": "result", "ok": false, "message": format!("'{s}' is not an available Safe Clean category") }));
            return 2;
        }
    }
    common::emit(&json!({ "event": "start", "categories": selected }));
    crate::set_activity("cleaning", "Starting cleanup…");
    let code = clean_selected(cfg, &selected, &available);
    crate::set_activity("", "");
    code
}

fn clean_selected(cfg: &Config, selected: &[String], available: &HashMap<String, Value>) -> i32 {
    let started = Instant::now();
    let before = free_bytes();
    let measured_before: HashMap<String, u64> = selected.iter().filter_map(|s| measure_category(s).map(|b| (s.clone(), b))).collect();
    let mut results: Vec<Value> = vec![];
    let mut sink = |l: &str| log(l);
    let step = |id: &str, status: &str| {
        if status == "running" {
            let label = available.get(id).and_then(|i| i["label"].as_str()).unwrap_or(id);
            crate::set_activity("cleaning", &format!("Cleaning: {label}"));
        }
        common::emit(&json!({ "event": "step", "id": id, "status": status }));
    };

    for s in selected {
        let ok = match s.as_str() {
            "trash" => {
                step(s, "running");
                let ok = stream_cmd("gio", &["trash", "--empty"], &mut sink);
                // gio hands the deletion to gvfsd, which finishes asynchronously
                // (files → expunged → unlinked). Wait so the measurement is real.
                if ok { wait_trash_drained(); }
                ok
            }
            "thumbnails" => { step(s, "running"); let r = empty_dir_contents(&thumbnails_dir()); if let Err(e) = &r { log(&e.to_string()); } r.is_ok() }
            "flatpak-unused" => {
                step(s, "running");
                let d = &available[s]["details"];
                let mut ok = true;
                if d["user"].as_array().is_some_and(|a| !a.is_empty()) {
                    ok &= stream_cmd("flatpak", &["uninstall", "--unused", "--user", "-y", "--noninteractive"], &mut sink);
                }
                if d["system"].as_array().is_some_and(|a| !a.is_empty()) {
                    ok &= stream_cmd("flatpak", &["uninstall", "--unused", "--system", "-y", "--noninteractive"], &mut sink);
                }
                ok
            }
            "package-caches" => {
                step(s, "running");
                let mut ok = true;
                for (tool, p) in package_cache_dirs() {
                    log(&format!("Clearing {tool} cache at {}", p.display()));
                    let r = match tool {
                        "uv" if common::have("uv") => stream_cmd("uv", &["cache", "clean"], &mut sink),
                        "npm" if common::have("npm") => stream_cmd("npm", &["cache", "clean", "--force"], &mut sink),
                        _ => empty_dir_contents(&p).is_ok(),
                    };
                    ok &= r;
                }
                ok
            }
            "containers" => {
                step(s, "running");
                stream_cmd("docker", &["image", "prune", "-f"], &mut sink) & stream_cmd("docker", &["builder", "prune", "-f"], &mut sink)
            }
            _ => continue,
        };
        step(s, if ok { "ok" } else { "failed" });
        results.push(json!({ "id": s, "ok": ok }));
    }

    // Root categories in one pkexec call.
    let want_gens = selected.iter().any(|s| s == "nix-generations");
    let want_gc = want_gens || selected.iter().any(|s| s == "nix-garbage");
    let want_journal = selected.iter().any(|s| s == "journal");
    if want_gens {
        // User-profile generations belong to neo: no root needed.
        let (del, _) = deletable_user_generations(cfg.clean.keep_user_generations);
        if !del.is_empty() {
            let profile = user_profile_dir().join("profile").to_string_lossy().into_owned();
            let nums: Vec<String> = del.iter().map(|n| n.to_string()).collect();
            let mut a = vec!["-p", profile.as_str(), "--delete-generations"];
            a.extend(nums.iter().map(String::as_str));
            stream_cmd("nix-env", &a, &mut sink);
        }
    }
    if want_gc || want_journal {
        for id in selected.iter().filter(|s| ["nix-generations", "nix-garbage", "journal"].contains(&s.as_str())) {
            step(id, "running");
        }
        let exe = fs::canonicalize("/proc/self/exe").map(|p| p.to_string_lossy().into_owned()).unwrap_or_default();
        let mut a: Vec<String> = vec![exe, "privileged".into(), "clean".into()];
        if want_gens {
            let (del, _) = deletable_system_generations(cfg.clean.keep_system_generations);
            if !del.is_empty() {
                a.push("--generations".into());
                a.push(del.iter().map(|n| n.to_string()).collect::<Vec<_>>().join(","));
                a.push("--keep".into());
                a.push(cfg.clean.keep_system_generations.to_string());
            }
        }
        if want_gc { a.push("--gc".into()); }
        if want_journal { a.push("--journal".into()); a.push(cfg.clean.journal_retention.clone()); }
        let refs: Vec<&str> = a.iter().map(String::as_str).collect();
        let mut done_ok = false;
        let mut granted = false;
        let mut other: Vec<String> = vec![];
        // The password prompt appears now; the UI shows "waiting for
        // authentication" until the root half speaks for the first time.
        common::emit(&json!({ "event": "auth", "state": "waiting",
                              "message": "Authentication required — enter your password in the prompt." }));
        crate::set_activity("cleaning", "Waiting for authentication…");
        let mut relay = |l: &str| match serde_json::from_str::<Value>(l) {
            Ok(v) if v.get("event").is_some() => {
                if !granted {
                    granted = true;
                    common::emit(&json!({ "event": "auth", "state": "granted" }));
                }
                if v["event"] == "done" { done_ok = v["ok"] == true; }
                common::emit(&v);
            }
            _ => { other.push(l.to_string()); log(l) }
        };
        let ok = stream_cmd("pkexec", &refs, &mut relay) && done_ok;
        let auth_error = if granted { None } else {
            Some(common::pkexec_failure(&other).unwrap_or("Authentication did not complete."))
        };
        if let Some(reason) = auth_error {
            common::emit(&json!({ "event": "auth", "state": "failed", "message": reason }));
        }
        for id in selected.iter().filter(|s| ["nix-generations", "nix-garbage", "journal"].contains(&s.as_str())) {
            step(id, if ok { "ok" } else if auth_error.is_some() { "skipped" } else { "failed" });
            results.push(json!({ "id": id, "ok": ok, "error": auth_error }));
        }
        if let Some(reason) = auth_error {
            log(&format!("{reason} The root categories were not cleaned."));
        } else if !ok {
            log("A privileged cleanup command failed — see the log above.");
        }
    }

    // Actual effect: per-category re-measurement where a category can be
    // measured directly, plus the filesystem free-space delta (which also
    // includes whatever else wrote to disk meanwhile).
    std::thread::sleep(Duration::from_secs(1));
    let after = free_bytes();
    let fs_delta = after.saturating_sub(before);
    let mut per_cat = serde_json::Map::new();
    for (id, b) in &measured_before {
        if let Some(a) = measure_category(id) {
            per_cat.insert(id.clone(), json!({ "before": b, "after": a, "reclaimed": b.saturating_sub(a) }));
        }
    }
    let direct: u64 = per_cat.values().filter_map(|v| v["reclaimed"].as_u64()).sum();
    let unmeasured = selected.iter().any(|s| !per_cat.contains_key(s));
    // Categories without a direct measurement (Nix, Flatpak, Docker) are only
    // visible in the filesystem delta; otherwise prefer the direct numbers.
    let reclaimed = if unmeasured { fs_delta.max(direct) } else { direct };
    let est: u64 = selected.iter().filter_map(|s| available[s]["estimate"].as_u64()).sum();
    common::emit(&json!({ "event": "phase", "text": "Rescanning…" }));
    crate::set_activity("cleaning", "Rescanning to measure the result…");
    let rescan_ok = match scan::run_scan(cfg) {
        Ok(doc) => common::write_json(&crate::scan_file(), &doc, 0o600).is_ok(),
        Err(_) => false,
    };
    let all_ok = results.iter().all(|r| r["ok"] == true);
    let summary = json!({
        "at": common::now_unix(), "categories": selected, "results": results,
        "estimatedBytes": est, "reclaimedBytes": reclaimed, "freeBefore": before, "freeAfter": after,
        "filesystemDelta": fs_delta, "perCategory": per_cat,
        "measuredBy": if unmeasured { "change in available space on local filesystems (includes other disk activity)" }
                      else { "size of the cleaned locations before and after" },
        "ok": all_ok, "rescanned": rescan_ok,
    });
    let _ = common::write_json(&common::state_dir(APP).join("last-clean.json"), &summary, 0o600);
    if cfg.notifications.enabled {
        common::notify("Storage Optimizer", "drive-harddisk", &format!("Storage cleanup reclaimed {}", common::human_bytes(reclaimed)),
                       if all_ok { "" } else { "Some categories failed — see the log in Storage Optimizer." });
    }
    let duration_ms = started.elapsed().as_millis() as u64;
    let duration = common::format_duration_ms(duration_ms);
    let mut r = summary.clone();
    r["event"] = json!("result");
    r["durationMs"] = json!(duration_ms);
    r["duration"] = json!(duration);
    r["message"] = json!(format!(
        "Reclaimed {} (estimated {}) in {}",
        common::human_bytes(reclaimed),
        common::human_bytes(est),
        duration
    ));
    common::emit(&r);
    if all_ok { 0 } else { 1 }
}

// ------------------------------------------------------------------ trash one item

fn protected_reason(p: &Path, build_output: bool) -> Option<String> {
    let home = common::home();
    if p == home || !p.starts_with(&home) {
        return Some("Only items inside your home directory can be moved to the Trash here".into());
    }
    if p.strip_prefix(&home).map(|r| r.components().count()).unwrap_or(0) < 2 && p.is_dir() {
        return Some("Top-level folders of your home directory are never trashed from here".into());
    }
    for a in p.ancestors().skip(1) {
        if a.join(".git").exists() && p.is_dir() && !build_output {
            return Some(format!("Inside Git repository {}", a.display()));
        }
        if a == home { break; }
    }
    None
}

pub fn trash_main(_cfg: &Config, path: &str) -> i32 {
    let p = PathBuf::from(path);
    let Some(mut doc) = common::read_json(&crate::scan_file()) else {
        common::emit(&json!({ "ok": false, "message": "No scan results" }));
        return 1;
    };
    let item = doc["largeItems"].as_array().and_then(|a| a.iter().find(|i| i["path"] == path).cloned());
    let Some(item) = item else {
        common::emit(&json!({ "ok": false, "message": "Only items listed under Large Items can be moved to the Trash" }));
        return 1;
    };
    if item["trashable"] != true {
        common::emit(&json!({ "ok": false, "message": format!("This item is protected: {}", item["protected"].as_str().or(item["hint"].as_str()).unwrap_or("not a removable item")) }));
        return 1;
    }
    if p.join(".git").exists() {
        common::emit(&json!({ "ok": false, "message": "Refusing to trash a Git repository" }));
        return 1;
    }
    if let Some(r) = protected_reason(&p, item["classification"] == "Reproducible Build") {
        common::emit(&json!({ "ok": false, "message": r }));
        return 1;
    }
    let Ok(meta) = fs::symlink_metadata(&p) else {
        common::emit(&json!({ "ok": false, "message": "The item no longer exists" }));
        return 1;
    };
    if meta.file_type().is_symlink() {
        common::emit(&json!({ "ok": false, "message": "Refusing to trash a symlink" }));
        return 1;
    }
    let r = common::run("gio", &["trash", "--", path], Duration::from_secs(600));
    if !r.ok {
        common::emit(&json!({ "ok": false, "message": format!("gio trash failed: {}", r.stderr.trim()) }));
        return 1;
    }
    if let Some(items) = doc["largeItems"].as_array_mut() {
        items.retain(|i| i["path"] != path);
    }
    let _ = common::write_json(&crate::scan_file(), &doc, 0o600);
    common::emit(&json!({ "ok": true, "message": format!("Moved to Trash: {} ({}). Empty the Trash to free the space.", path, common::human_bytes(item["bytes"].as_u64().unwrap_or(0))) }));
    0
}

// ------------------------------------------------------------------ root half

pub fn privileged_main(args: &[String]) -> i32 {
    let done = |ok: bool, msg: &str| common::emit(&json!({ "event": "done", "ok": ok, "message": msg }));
    if unsafe { libc::geteuid() } != 0 {
        eprintln!("privileged: must be run through pkexec");
        return 2;
    }
    std::env::set_var("HOME", "/root");
    if args.first().map(String::as_str) != Some("clean") {
        done(false, "unknown privileged action");
        return 2;
    }
    let get = |k: &str| args.iter().position(|a| a == k).and_then(|i| args.get(i + 1)).cloned();
    let gens: Vec<u64> = match get("--generations") {
        Some(s) => match s.split(',').map(|x| x.parse::<u64>()).collect::<Result<Vec<_>, _>>() {
            Ok(v) => v,
            Err(_) => { done(false, "invalid generation list"); return 2; }
        },
        None => vec![],
    };
    let keep: usize = get("--keep").and_then(|k| k.parse().ok()).unwrap_or(3);
    let gc = args.iter().any(|a| a == "--gc");
    let journal = get("--journal");
    if journal.as_deref().is_some_and(|j| parse_retention(j).is_none()) {
        done(false, "invalid journal retention");
        return 2;
    }
    let mut sink = |l: &str| log(l);
    let mut ok = true;

    if !gens.is_empty() {
        // Re-validate as root: never the current, booted, boot-default or newest N.
        let (allowed, _) = deletable_system_generations(keep);
        if let Some(bad) = gens.iter().find(|g| !allowed.contains(g)) {
            done(false, &format!("Refusing to delete generation {bad}: it is protected"));
            return 1;
        }
        let nums: Vec<String> = gens.iter().map(|n| n.to_string()).collect();
        let mut a = vec!["-p", "/nix/var/nix/profiles/system", "--delete-generations"];
        a.extend(nums.iter().map(String::as_str));
        ok &= stream_cmd("nix-env", &a, &mut sink);
        if ok {
            // Regenerate boot entries for the boot-default generation, exactly
            // as `nixos-rebuild boot` would, so deleted generations leave the menu.
            log("Updating boot menu entries for the remaining generations…");
            ok &= stream_cmd("/nix/var/nix/profiles/system/bin/switch-to-configuration", &["boot"], &mut sink);
        }
    }
    if gc && ok {
        common::emit(&json!({ "event": "phase", "text": "Collecting Nix garbage…" }));
        ok &= stream_cmd("nix-store", &["--gc"], &mut sink);
    }
    if let Some(j) = journal {
        common::emit(&json!({ "event": "phase", "text": "Vacuuming journal…" }));
        ok &= stream_cmd("journalctl", &[&format!("--vacuum-time={j}")], &mut sink);
    }
    done(ok, if ok { "Privileged cleanup finished" } else { "Privileged cleanup failed" });
    if ok { 0 } else { 1 }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::CleanDefaults;

    #[test]
    fn parse_retention_journalctl_subset() {
        assert_eq!(parse_retention("4weeks"), Some(4 * 7 * 86400));
        assert_eq!(parse_retention("2w"), Some(2 * 7 * 86400));
        assert_eq!(parse_retention("1month"), Some(30 * 86400));
        assert_eq!(parse_retention("30d"), Some(30 * 86400));
        assert_eq!(parse_retention("12h"), Some(12 * 3600));
        assert_eq!(parse_retention("0d"), None);
        assert_eq!(parse_retention("forever"), None);
        assert_eq!(parse_retention(""), None);
    }

    #[test]
    fn generation_keep_reason_protects_critical_and_recent() {
        assert_eq!(generation_keep_reason(5, 3, true, false, false), Some("current"));
        assert_eq!(generation_keep_reason(5, 3, false, true, false), Some("booted"));
        assert_eq!(generation_keep_reason(5, 3, false, false, true), Some("boot default"));
        assert_eq!(generation_keep_reason(0, 3, false, false, false), Some("recent (kept)"));
        assert_eq!(generation_keep_reason(2, 3, false, false, false), Some("recent (kept)"));
        assert_eq!(generation_keep_reason(3, 3, false, false, false), None);
        // keep=0 still keeps the newest one
        assert_eq!(generation_keep_reason(0, 0, false, false, false), Some("recent (kept)"));
        assert_eq!(generation_keep_reason(1, 0, false, false, false), None);
    }

    #[test]
    fn safe_clean_defaults_vs_advanced() {
        let d = CleanDefaults::default();
        assert!(d.nix_generations && d.nix_garbage && d.flatpak_unused && d.thumbnails && d.journal);
        assert!(!d.trash && !d.package_caches && !d.containers);
    }

    #[test]
    fn du_measures_temp_tree_without_touching_home() {
        let root = std::env::temp_dir().join(format!("storage-opt-du-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("sub")).unwrap();
        fs::write(root.join("a.bin"), vec![0u8; 4096]).unwrap();
        fs::write(root.join("sub/b.bin"), vec![1u8; 8192]).unwrap();
        let (bytes, files) = du(&root);
        assert_eq!(files, 2);
        // allocated blocks are at least the logical sizes (filesystem may round up)
        assert!(bytes >= 4096 + 8192, "bytes={bytes}");
        let _ = fs::remove_dir_all(&root);
    }
}
