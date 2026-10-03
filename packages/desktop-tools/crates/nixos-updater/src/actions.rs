//! Mutating actions. Every action is started explicitly from the UI and
//! streams JSON-lines events:
//!   {"event":"phase","text":"Dry-build (nixos-rebuild build)…","cancellable":true}
//!   {"event":"log","line":"…"}
//!   {"event":"step","id":"rebuild","status":"ok"}
//!   {"event":"diff","changes":[…]}
//!   {"event":"result","ok":true,"message":"…",…}
//!
//! Root work goes through `pkexec <this binary> privileged <action>`, which
//! accepts only a fixed set of actions and validated arguments, and takes the
//! flake path from the root-owned /etc/nixos-updater/system.json — never from
//! user input. Before flake.nix/flake.lock are touched, the originals are
//! copied to /var/lib/nixos-updater/backups/<id>; revert restores a file only
//! if it is still exactly what this tool wrote, so later edits are never lost.

use crate::{common, Config, APP};
use serde_json::{json, Value};
use std::fs;
use std::io::{BufRead, BufReader};
use std::os::unix::fs::{chown, MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

// ================================================================= plan

pub fn plan(st: &Value) -> Value {
    let mut steps = vec![];
    let mut warnings: Vec<String> = vec![];
    let fu = st["flatpak"]["user"]["updates"].as_array().cloned().unwrap_or_default();
    let fs_ = st["flatpak"]["system"]["updates"].as_array().cloned().unwrap_or_default();
    let refs = |a: &[Value]| a.iter().filter_map(|u| u["ref"].as_str().map(String::from)).collect::<Vec<_>>();
    if !fu.is_empty() {
        steps.push(json!({
            "id": "flatpak-user", "title": "Update user Flatpaks",
            "detail": refs(&fu), "commands": ["flatpak update --user -y --noninteractive"],
            "privileged": false, "default": true }));
    }
    if !fs_.is_empty() {
        steps.push(json!({
            "id": "flatpak-system", "title": "Update system Flatpaks",
            "detail": refs(&fs_), "commands": ["flatpak update --system -y --noninteractive"],
            "privileged": false, "authNote": "Flatpak may ask for authentication through polkit.", "default": true }));
    }
    let mods: Vec<String> = st["mods"]["mods"].as_array().map(|a| {
        a.iter().filter(|m| m["updateAvailable"] == true).filter_map(|m| m["id"].as_str().map(String::from)).collect()
    }).unwrap_or_default();
    if !mods.is_empty() {
        steps.push(json!({
            "id": "mods", "title": "Update Ambxst mods", "detail": mods,
            "commands": mods.iter().map(|m| format!("ambxst mods update {m}")).collect::<Vec<_>>(),
            "privileged": false, "default": true }));
    }
    let mut flake_changes = false;
    if st["nixpkgs"]["updateAvailable"] == true {
        flake_changes = true;
        let from = st["nixpkgs"]["current"].as_str().unwrap_or("?");
        let to = st["nixpkgs"]["latest"].as_str().unwrap_or("?");
        steps.push(json!({
            "id": "nixpkgs", "title": "Move nixpkgs to the latest channel release",
            "detail": [format!("{from} → {to}"), "flake.nix: nixpkgs.url is rewritten to the new release".to_string(),
                       "flake.lock: nixpkgs is re-locked (nix flake update nixpkgs)".to_string()],
            "release": to,
            "commands": [format!("rewrite nixpkgs.url in flake.nix to …/{to}/nixexprs.tar.xz"), "nix flake update nixpkgs".to_string()],
            "privileged": true, "default": true }));
    }
    let outdated: Vec<String> = st["flakeInputs"].as_array().map(|a| {
        a.iter().filter(|i| i["outdated"] == true).filter_map(|i| i["name"].as_str().map(String::from)).collect()
    }).unwrap_or_default();
    if !outdated.is_empty() {
        flake_changes = true;
        steps.push(json!({
            "id": "flake-inputs", "title": "Update branch-following flake inputs", "detail": outdated.clone(),
            "inputs": outdated.clone(),
            "commands": [format!("nix flake update {}", outdated.join(" "))],
            "privileged": true, "default": true }));
    }
    let pinned: Vec<String> = st["flakeInputs"].as_array().map(|a| {
        a.iter().filter(|i| i["newerUpstream"] == true && i["updatableByLock"] != true && i["name"] != "nixpkgs")
            .map(|i| format!("{} ({}-pinned)", i["name"].as_str().unwrap_or("?"), i["pin"].as_str().unwrap_or("?"))).collect()
    }).unwrap_or_default();
    if !pinned.is_empty() {
        warnings.push(format!(
            "Pinned inputs with newer upstream versions are not changed automatically: {}. Edit flake.nix deliberately to move them.",
            pinned.join(", ")));
    }
    let attr = crate::system_info().flake_attr;
    steps.push(json!({
        "id": "rebuild", "title": "Validate, dry-build & activate NixOS",
        "detail": ["Validate flake metadata, dry-build with nixos-rebuild build (cancellable), then activate with switch.",
                   "If the build fails nothing is activated and the current system stays in place.",
                   "Activation cannot be cancelled; a post-validate step reports the new generation."],
        "commands": [format!("nix flake metadata --json --no-write-lock-file {}", crate::system_info().flake_path),
                     format!("nixos-rebuild build --flake {}#{attr}", crate::system_info().flake_path),
                     format!("nixos-rebuild switch --flake {}#{attr}", crate::system_info().flake_path)],
        "privileged": true, "default": flake_changes }));
    let unrelated = st["flakeRepo"]["unrelatedChanges"].as_array().map(|a| a.len()).unwrap_or(0);
    if unrelated > 0 {
        warnings.push(format!("{unrelated} uncommitted change(s) in the flake repository are preserved and will be part of the rebuild."));
    }
    if st["flakeRepo"]["git"] == false {
        warnings.push("The flake directory is not a Git repository; flake.nix/flake.lock are backed up before changes and can be reverted from the app.".into());
    }
    if st["kernel"]["updateChangesKernel"] == true {
        warnings.push(format!("The nixpkgs update brings kernel {}. A reboot will be required to use it.",
            st["kernel"]["availableAfterUpdate"].as_str().unwrap_or("?")));
    }
    if st["ambxst"]["updateAvailable"] == true {
        warnings.push(format!("Ambxst {} is available upstream (running {}). It is pinned in {} and is not updated by this plan.",
            st["ambxst"]["latestTag"].as_str().unwrap_or("?"), st["ambxst"]["version"].as_str().unwrap_or("?"),
            st["ambxst"]["pinFile"].as_str().unwrap_or("the Ambxst module")));
    }
    json!({ "generatedAt": common::now_unix(), "basedOnCheck": st["checkedAt"], "steps": steps, "warnings": warnings })
}

// ================================================================= streaming

enum Line {
    Out(String),
    Err(String),
}

/// Run a child, streaming its output as log events. `cancel` is polled; when
/// it returns true and the phase is cancellable, the child is killed.
/// Returns (exit ok, was cancelled, captured tail of output).
fn stream(
    program: &str,
    args: &[&str],
    cwd: Option<&Path>,
    cancellable: bool,
    cancel: &dyn Fn() -> bool,
    sink: &mut dyn FnMut(&str),
) -> (bool, bool, Vec<String>) {
    let mut cmd = Command::new(program);
    cmd.args(args).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
    if let Some(c) = cwd {
        cmd.current_dir(c);
    }
    // Own process group so a cancel can stop the whole build tree.
    use std::os::unix::process::CommandExt;
    cmd.process_group(0);
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            let m = format!("failed to start {program}: {e}");
            sink(&m);
            return (false, false, vec![m]);
        }
    };
    let (tx, rx) = mpsc::channel::<Line>();
    let so = child.stdout.take().unwrap();
    let se = child.stderr.take().unwrap();
    let tx2 = tx.clone();
    let h1 = std::thread::spawn(move || {
        for l in BufReader::new(so).lines().map_while(Result::ok) {
            let _ = tx.send(Line::Out(l));
        }
    });
    let h2 = std::thread::spawn(move || {
        for l in BufReader::new(se).lines().map_while(Result::ok) {
            let _ = tx2.send(Line::Err(l));
        }
    });
    let mut tail: Vec<String> = vec![];
    let mut was_cancelled = false;
    loop {
        match rx.recv_timeout(Duration::from_millis(200)) {
            Ok(Line::Out(l)) | Ok(Line::Err(l)) => {
                sink(&l);
                tail.push(l);
                if tail.len() > 60 {
                    tail.remove(0);
                }
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
            Err(mpsc::RecvTimeoutError::Timeout) => {}
        }
        if cancellable && !was_cancelled && cancel() {
            was_cancelled = true;
            sink("Cancelling…");
            unsafe { libc::kill(-(child.id() as i32), libc::SIGTERM) };
        }
    }
    let _ = h1.join();
    let _ = h2.join();
    let ok = child.wait().map(|s| s.success()).unwrap_or(false);
    (ok && !was_cancelled, was_cancelled, tail)
}

fn ev(v: Value) {
    common::emit(&v);
}

// ================================================================= user side

struct Run {
    log: fs::File,
    log_path: PathBuf,
    started: Instant,
}

impl Run {
    fn new(action: &str) -> Run {
        let dir = common::state_dir(APP).join("logs");
        let _ = fs::create_dir_all(&dir);
        prune_logs(&dir, 30);
        let ts = chrono_like(common::now_unix());
        let log_path = dir.join(format!("{ts}-{action}.log"));
        let log = fs::OpenOptions::new().create(true).append(true).open(&log_path).expect("log file");
        let _ = log.set_permissions(fs::Permissions::from_mode(0o600));
        Run { log, log_path, started: Instant::now() }
    }
    fn line(&mut self, l: &str) {
        use std::io::Write;
        let _ = writeln!(self.log, "{l}");
        ev(json!({ "event": "log", "line": l }));
    }
    fn elapsed_ms(&self) -> u64 {
        self.started.elapsed().as_millis() as u64
    }
}

fn prune_logs(dir: &Path, keep: usize) {
    let mut v: Vec<PathBuf> = fs::read_dir(dir).map(|r| r.flatten().map(|e| e.path()).collect()).unwrap_or_default();
    v.sort();
    if v.len() > keep {
        for p in &v[..v.len() - keep] {
            let _ = fs::remove_file(p);
        }
    }
}

/// UTC timestamp like 20260922T220239Z without pulling in a date crate.
fn chrono_like(t: i64) -> String {
    let days = t.div_euclid(86400);
    let secs = t.rem_euclid(86400);
    // Civil-from-days (Howard Hinnant).
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{y:04}{m:02}{d:02}T{:02}{:02}{:02}Z", secs / 3600, (secs % 3600) / 60, secs % 60)
}

fn cancel_file_for(uid: u32) -> PathBuf {
    PathBuf::from(format!("/run/user/{uid}/{APP}/cancel"))
}

/// Cancellation reaches both halves through one file: the user-side steps
/// poll it, and the root half polls it and decides whether the current phase
/// can be stopped safely (build: yes, activation: no).
fn cancel_requested() -> bool {
    common::cancelled() || cancel_file_for(common::uid()).exists()
}

pub fn request_cancel() -> i32 {
    let p = cancel_file_for(common::uid());
    let _ = fs::create_dir_all(p.parent().unwrap());
    match fs::write(&p, b"1") {
        Ok(_) => 0,
        Err(e) => {
            eprintln!("{e}");
            1
        }
    }
}

fn arg_value(args: &[String], key: &str) -> Option<String> {
    args.iter().position(|a| a == key).and_then(|i| args.get(i + 1)).cloned()
}

fn record_last_run(action: &str, ok: bool, message: &str, log: &Path) {
    let _ = common::write_json(
        &common::state_dir(APP).join("last-run.json"),
        &json!({ "action": action, "ok": ok, "message": message, "at": common::now_unix(), "log": log }),
        0o600,
    );
}

fn result(run: &mut Run, cfg: &Config, action: &str, ok: bool, message: &str, extra: Value) -> i32 {
    let duration_ms = run.elapsed_ms();
    let duration = common::format_duration_ms(duration_ms);
    run.line(&format!("== {message}  ({duration})"));
    record_last_run(action, ok, message, &run.log_path);
    let mut r = json!({
        "event": "result", "action": action, "ok": ok, "message": message,
        "log": run.log_path, "durationMs": duration_ms, "duration": duration,
    });
    if let (Some(o), Some(e)) = (r.as_object_mut(), extra.as_object()) {
        for (k, v) in e {
            o.insert(k.clone(), v.clone());
        }
    }
    ev(r);
    if cfg.notifications.enabled && cfg.notifications.results {
        common::notify("NixOS Updater", if ok { "system-software-update" } else { "dialog-error" }, message, "");
    }
    if ok { 0 } else { 1 }
}

/// Run one user-level command as a step.
fn user_step(run: &mut Run, id: &str, title: &str, program: &str, args: &[&str]) -> bool {
    ev(json!({ "event": "step", "id": id, "title": title, "status": "running" }));
    ev(json!({ "event": "phase", "text": format!("{title}…"), "cancellable": true }));
    run.line(&format!("$ {program} {}", args.join(" ")));
    let (ok, cancelled, _) = {
        let mut sink = |l: &str| run.line(l);
        stream(program, args, None, true, &cancel_requested, &mut sink)
    };
    let status = if cancelled { "cancelled" } else if ok { "ok" } else { "failed" };
    ev(json!({ "event": "step", "id": id, "status": status }));
    ok
}

/// Run a privileged sequence through pkexec, relaying its events.
fn privileged_step(run: &mut Run, args: &[String]) -> (bool, Vec<Value>) {
    let exe = fs::canonicalize("/proc/self/exe").unwrap_or_else(|_| PathBuf::from("nixos-updater-helper"));
    let exe = exe.to_string_lossy().into_owned();
    let mut a: Vec<&str> = vec![&exe, "privileged"];
    a.extend(args.iter().map(String::as_str));
    run.line(&format!("$ pkexec nixos-updater-helper privileged {}", args.join(" ")));
    let cancel_path = cancel_file_for(common::uid());
    let mut results = vec![];
    let mut ok_seen = false;
    // The password prompt appears now; the UI shows "waiting for
    // authentication" until the root half speaks for the first time.
    ev(json!({ "event": "auth", "state": "waiting",
               "message": "Authentication required — enter your password in the prompt." }));
    let mut granted = false;
    let (ok, _, tail) = {
        let mut sink = |l: &str| {
            // Relay structured events from the root half; raw lines are logs.
            match serde_json::from_str::<Value>(l) {
                Ok(v) if v.get("event").is_some() => {
                    if !granted {
                        granted = true;
                        ev(json!({ "event": "auth", "state": "granted" }));
                    }
                    if v["event"] == "log" {
                        run.line(v["line"].as_str().unwrap_or(""));
                    } else {
                        if v["event"] == "done" {
                            ok_seen = v["ok"] == true;
                        }
                        if v["event"] == "done" || v["event"] == "diff" {
                            results.push(v.clone());
                        }
                        ev(v);
                    }
                }
                _ => run.line(l),
            }
        };
        // Cancellation reaches the root process through a file it polls; it
        // decides whether the current phase can be stopped safely.
        let cancel = || {
            if common::cancelled() && !cancel_path.exists() {
                let _ = request_cancel();
            }
            false
        };
        stream("pkexec", &a, None, false, &cancel, &mut sink)
    };
    let _ = fs::remove_file(&cancel_path);
    if !granted {
        let reason = common::pkexec_failure(&tail).unwrap_or("Authentication did not complete.");
        run.line(reason);
        ev(json!({ "event": "auth", "state": "failed", "message": reason }));
        results.push(json!({ "event": "done", "ok": false, "message": reason }));
    }
    (ok && ok_seen, results)
}

pub fn apply_main(cfg: &Config, args: &[String]) -> i32 {
    let Some(action) = args.first().map(String::as_str) else {
        eprintln!("apply: missing action");
        return 2;
    };
    let Some(_lock) = common::try_lock(&crate::lock_file()) else {
        ev(json!({ "event": "result", "ok": false, "message": "Another update or check is already running." }));
        return 1;
    };
    let _ = fs::remove_file(cancel_file_for(common::uid())); // stale request
    let mut run = Run::new(action);
    ev(json!({ "event": "start", "action": action, "log": run.log_path }));
    let rest = &args[1..];

    let steps: Vec<String> = match action {
        "update-all" => arg_value(rest, "--steps").unwrap_or_default().split(',').filter(|s| !s.is_empty()).map(String::from).collect(),
        "flatpak-user" | "flatpak-system" | "mods" | "nixpkgs" | "flake-inputs" | "rebuild" => vec![action.to_string()],
        "revert-lock" => {
            let Some(id) = arg_value(rest, "--backup") else { return result(&mut run, cfg, action, false, "revert-lock needs --backup <id>", json!({})) };
            let (ok, res) = privileged_step(&mut run, &["revert".into(), "--backup".into(), id]);
            if ok {
                let _ = fs::remove_file(common::state_dir(APP).join("pending-revert.json"));
            }
            let msg = res.iter().rev().find_map(|r| r["message"].as_str().map(String::from))
                .unwrap_or_else(|| if ok { "Flake changes reverted".into() } else { "Revert failed".into() });
            return result(&mut run, cfg, action, ok, &msg, json!({}));
        }
        _ => return result(&mut run, cfg, action, false, &format!("unknown action {action}"), json!({})),
    };

    let mut done: Vec<String> = vec![];
    // User-level steps first (they cannot affect the NixOS build).
    for s in steps.iter() {
        if cancel_requested() {
            return result(&mut run, cfg, action, false, "Cancelled before completion", json!({ "completed": done }));
        }
        let ok = match s.as_str() {
            "flatpak-user" => user_step(&mut run, s, "Updating user Flatpaks", "flatpak", &["update", "--user", "-y", "--noninteractive"]),
            "flatpak-system" => user_step(&mut run, s, "Updating system Flatpaks", "flatpak", &["update", "--system", "-y", "--noninteractive"]),
            "mods" => {
                let st = crate::status::collect(cfg, None, false);
                let ids: Vec<String> = st["mods"]["mods"].as_array().map(|a| a.iter().filter_map(|m| m["id"].as_str().map(String::from)).collect()).unwrap_or_default();
                let mut ok = true;
                for id in ids {
                    ok &= user_step(&mut run, s, &format!("Updating mod {id}"), "ambxst", &["mods", "update", &id]);
                }
                if ok { run.line("Restart Ambxst (ambxst reload) to load the rebuilt mod generation."); }
                ok
            }
            _ => continue,
        };
        if !ok {
            return result(&mut run, cfg, action, false, &format!("Step '{s}' failed — later steps were not run"), json!({ "completed": done, "failedStep": s }));
        }
        done.push(s.clone());
    }

    // Root steps run in one pkexec session (one authentication).
    let mut root: Vec<String> = vec![];
    for s in ["nixpkgs", "flake-inputs", "rebuild"] {
        if steps.iter().any(|x| x == s) {
            root.push(s.to_string());
        }
    }
    if root.is_empty() {
        return result(&mut run, cfg, action, true, "Updates completed", json!({ "completed": done }));
    }
    let mut pargs: Vec<String> = vec!["sequence".into(), "--steps".into(), root.join(",")];
    if root.iter().any(|s| s == "nixpkgs") {
        let Some(rel) = arg_value(rest, "--release") else {
            return result(&mut run, cfg, action, false, "nixpkgs step needs --release (from the reviewed plan)", json!({}));
        };
        pargs.extend(["--release".into(), rel]);
    }
    if root.iter().any(|s| s == "flake-inputs") {
        let Some(inp) = arg_value(rest, "--inputs") else {
            return result(&mut run, cfg, action, false, "flake-inputs step needs --inputs (from the reviewed plan)", json!({}));
        };
        pargs.extend(["--inputs".into(), inp]);
    }
    if cancel_requested() {
        return result(&mut run, cfg, action, false, "Cancelled before the NixOS steps started", json!({ "completed": done }));
    }
    let (ok, res) = privileged_step(&mut run, &pargs);
    let done_ev = res.iter().rev().find(|r| r["event"] == "done").cloned().unwrap_or(json!({}));
    if let Some(b) = done_ev["backupId"].as_str() {
        // Remember the lock change so the app can offer a revert later.
        let _ = common::write_json(
            &common::state_dir(APP).join("pending-revert.json"),
            &json!({ "backupId": b, "at": common::now_unix(), "rebuildOk": done_ev["rebuildOk"], "diff": done_ev["diff"] }),
            0o600,
        );
    }
    let msg = done_ev["message"].as_str().map(String::from).unwrap_or_else(|| {
        if ok { "Update completed".into() } else { "Update failed — the current system was kept".into() }
    });
    result(&mut run, cfg, action, ok, &msg, json!({
        "completed": done,
        "rebootRequired": done_ev["rebootRequired"],
        "newKernel": done_ev["newKernel"],
        "generationBefore": done_ev["generationBefore"],
        "generationAfter": done_ev["generationAfter"],
        "backupId": done_ev["backupId"],
        "revertAvailable": done_ev["backupId"].is_string(),
        "diff": done_ev["diff"],
    }))
}

// ================================================================= root side

fn valid_release(r: &str) -> bool {
    // nixos-26.11pre1077996.6774f7bc2537 or nixos-26.05.1234.abcdef123456
    let Some(rest) = r.strip_prefix("nixos-") else { return false };
    r.len() < 80 && rest.chars().all(|c| c.is_ascii_alphanumeric() || c == '.') && rest.chars().next().is_some_and(|c| c.is_ascii_digit())
}

fn valid_ident(s: &str) -> bool {
    !s.is_empty() && s.len() < 64 && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

fn plog(l: &str) {
    ev(json!({ "event": "log", "line": l }));
}

fn backup_root(sys: &crate::SystemInfo) -> PathBuf {
    Path::new(&sys.state_dir).join("backups")
}

struct Backup {
    id: String,
    dir: PathBuf,
}

fn make_backup(sys: &crate::SystemInfo) -> std::io::Result<Backup> {
    let id = chrono_like(common::now_unix());
    let dir = backup_root(sys).join(&id);
    fs::create_dir_all(dir.join("before"))?;
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o700))?;
    for f in ["flake.nix", "flake.lock"] {
        fs::copy(Path::new(&sys.flake_path).join(f), dir.join("before").join(f))?;
    }
    Ok(Backup { id, dir })
}

fn finish_backup(b: &Backup, sys: &crate::SystemInfo, meta: Value) -> std::io::Result<()> {
    fs::create_dir_all(b.dir.join("after"))?;
    for f in ["flake.nix", "flake.lock"] {
        fs::copy(Path::new(&sys.flake_path).join(f), b.dir.join("after").join(f))?;
    }
    common::write_json(&b.dir.join("manifest.json"), &meta, 0o600)
}

/// Keep the original owner/mode after root rewrites a user-owned file.
fn restore_owner(path: &Path, uid: u32, gid: u32, mode: u32) {
    let _ = chown(path, Some(uid), Some(gid));
    let _ = fs::set_permissions(path, fs::Permissions::from_mode(mode & 0o7777));
}

fn lock_summary(path: &Path) -> Vec<(String, String)> {
    let Some(lock) = common::read_json(path) else { return vec![] };
    let root = lock["root"].as_str().unwrap_or("root").to_string();
    let mut v = vec![];
    if let Some(inputs) = lock["nodes"][&root]["inputs"].as_object() {
        for (name, r) in inputs {
            if let Some(n) = r.as_str() {
                let l = &lock["nodes"][n]["locked"];
                let id = l["rev"].as_str().or(l["url"].as_str()).unwrap_or("?").to_string();
                v.push((name.clone(), id));
            }
        }
    }
    v
}

fn lock_diff(before: &Path, after: &Path) -> Vec<Value> {
    let a = lock_summary(before);
    let b = lock_summary(after);
    b.iter()
        .filter_map(|(n, new)| {
            let old = a.iter().find(|(m, _)| m == n).map(|x| x.1.clone()).unwrap_or_default();
            (old != *new).then(|| json!({ "input": n, "from": old, "to": new }))
        })
        .collect()
}

pub fn privileged_main(args: &[String]) -> i32 {
    if unsafe { libc::geteuid() } != 0 {
        eprintln!("privileged: must be run through pkexec");
        return 2;
    }
    std::env::set_var("HOME", "/root");
    let sys = crate::system_info();
    if sys.flake_attr.is_empty() || !valid_ident(&sys.flake_attr) || !Path::new(&sys.flake_path).join("flake.nix").is_file() {
        ev(json!({ "event": "done", "ok": false, "message": "/etc/nixos-updater/system.json is missing or invalid" }));
        return 1;
    }
    let caller: Option<u32> = std::env::var("PKEXEC_UID").ok().and_then(|s| s.parse().ok());
    let cancel_path = caller.map(cancel_file_for);
    let cancel = move || cancel_path.as_ref().is_some_and(|p| p.exists());

    let action = args.first().map(String::as_str).unwrap_or("");
    let rest = &args[1..];
    match action {
        "sequence" => {
            let steps: Vec<String> = arg_value(rest, "--steps").unwrap_or_default().split(',').map(String::from).collect();
            if steps.is_empty() || steps.iter().any(|s| !["nixpkgs", "flake-inputs", "rebuild"].contains(&s.as_str())) {
                ev(json!({ "event": "done", "ok": false, "message": "invalid steps" }));
                return 2;
            }
            let release = arg_value(rest, "--release");
            let inputs: Vec<String> = arg_value(rest, "--inputs").unwrap_or_default().split(',').filter(|s| !s.is_empty()).map(String::from).collect();
            if release.as_deref().is_some_and(|r| !valid_release(r)) || inputs.iter().any(|i| !valid_ident(i)) {
                ev(json!({ "event": "done", "ok": false, "message": "invalid release or input name" }));
                return 2;
            }
            sequence(&sys, &steps, release.as_deref(), &inputs, &cancel)
        }
        "revert" => {
            let Some(id) = arg_value(rest, "--backup").filter(|s| s.chars().all(|c| c.is_ascii_alphanumeric()) && s.len() < 32) else {
                ev(json!({ "event": "done", "ok": false, "message": "invalid backup id" }));
                return 2;
            };
            revert(&sys, &id)
        }
        _ => {
            ev(json!({ "event": "done", "ok": false, "message": "unknown privileged action" }));
            2
        }
    }
}

fn sequence(sys: &crate::SystemInfo, steps: &[String], release: Option<&str>, inputs: &[String], cancel: &dyn Fn() -> bool) -> i32 {
    let flake = Path::new(&sys.flake_path);
    let nix_file = flake.join("flake.nix");
    let lock_file = flake.join("flake.lock");
    let meta_nix = fs::metadata(&nix_file).ok();
    let meta_lock = fs::metadata(&lock_file).ok();
    let mut backup: Option<Backup> = None;
    let mut changes: Vec<Value> = vec![];
    let mut manifest = json!({ "createdAt": common::now_unix(), "flakePath": sys.flake_path });
    let mut sink = |l: &str| plog(l);

    let wants_lock = steps.iter().any(|s| s == "nixpkgs" || s == "flake-inputs");
    if wants_lock {
        match make_backup(sys) {
            Ok(b) => {
                plog(&format!("Backed up flake.nix and flake.lock to {}", b.dir.display()));
                backup = Some(b);
            }
            Err(e) => {
                ev(json!({ "event": "done", "ok": false, "message": format!("Could not back up flake files: {e}") }));
                return 1;
            }
        }
    }

    let fail = |msg: String, backup: &Option<Backup>, changes: &Vec<Value>| -> i32 {
        ev(json!({ "event": "done", "ok": false, "message": msg, "rebuildOk": false,
                   "backupId": backup.as_ref().filter(|_| !changes.is_empty()).map(|b| b.id.clone()), "diff": changes }));
        1
    };

    for step in steps {
        if cancel() {
            return fail("Cancelled".into(), &backup, &changes);
        }
        match step.as_str() {
            "nixpkgs" => {
                ev(json!({ "event": "step", "id": "nixpkgs", "status": "running" }));
                ev(json!({ "event": "phase", "text": "Updating nixpkgs…", "cancellable": true }));
                let release = release.unwrap();
                let text = fs::read_to_string(&nix_file).unwrap_or_default();
                let lock = common::read_json(&lock_file).unwrap_or(Value::Null);
                let old_url = lock["nodes"]["nixpkgs"]["original"]["url"].as_str().unwrap_or("").to_string();
                let Some(series_prefix) = old_url.rsplitn(3, '/').nth(2).map(String::from) else {
                    return fail("nixpkgs is not a releases.nixos.org URL".into(), &backup, &changes);
                };
                let new_url = format!("{series_prefix}/{release}/nixexprs.tar.xz");
                if text.matches(&old_url).count() != 1 {
                    return fail(format!("Expected exactly one occurrence of the nixpkgs URL in flake.nix; found {}. Not editing.", text.matches(&old_url).count()), &backup, &changes);
                }
                if old_url != new_url {
                    let new_text = text.replacen(&old_url, &new_url, 1);
                    if let Err(e) = common::write_atomic(&nix_file, new_text.as_bytes(), 0o644) {
                        return fail(format!("write flake.nix: {e}"), &backup, &changes);
                    }
                    if let Some(m) = &meta_nix { restore_owner(&nix_file, m.uid(), m.gid(), m.mode()); }
                    plog(&format!("flake.nix: nixpkgs.url {old_url} → {new_url}"));
                    manifest["nixpkgsUrl"] = json!({ "from": old_url, "to": new_url });
                }
                let (ok, c, _) = stream("nix", &["flake", "update", "nixpkgs", "--flake", &sys.flake_path], None, true, cancel, &mut sink);
                if let Some(m) = &meta_lock { restore_owner(&lock_file, m.uid(), m.gid(), m.mode()); }
                changes = lock_diff(&backup.as_ref().unwrap().dir.join("before/flake.lock"), &lock_file);
                if !ok {
                    let b = backup.as_ref().unwrap();
                    let _ = finish_backup(b, sys, manifest.clone());
                    ev(json!({ "event": "step", "id": "nixpkgs", "status": if c { "cancelled" } else { "failed" } }));
                    if old_url != new_url && changes.is_empty() {
                        changes.push(json!({ "input": "nixpkgs (flake.nix only)", "from": old_url, "to": new_url }));
                    }
                    return fail(if c { "Cancelled while locking nixpkgs".into() } else { "nix flake update nixpkgs failed".into() }, &backup, &changes);
                }
                ev(json!({ "event": "step", "id": "nixpkgs", "status": "ok" }));
            }
            "flake-inputs" => {
                ev(json!({ "event": "step", "id": "flake-inputs", "status": "running" }));
                ev(json!({ "event": "phase", "text": "Updating flake inputs…", "cancellable": true }));
                let mut a: Vec<&str> = vec!["flake", "update"];
                a.extend(inputs.iter().map(String::as_str));
                a.extend(["--flake", &sys.flake_path]);
                let (ok, c, _) = stream("nix", &a, None, true, cancel, &mut sink);
                if let Some(m) = &meta_lock { restore_owner(&lock_file, m.uid(), m.gid(), m.mode()); }
                changes = lock_diff(&backup.as_ref().unwrap().dir.join("before/flake.lock"), &lock_file);
                if !ok {
                    let _ = finish_backup(backup.as_ref().unwrap(), sys, manifest.clone());
                    ev(json!({ "event": "step", "id": "flake-inputs", "status": if c { "cancelled" } else { "failed" } }));
                    return fail("nix flake update failed".into(), &backup, &changes);
                }
                ev(json!({ "event": "step", "id": "flake-inputs", "status": "ok" }));
            }
            _ => {}
        }
    }

    if let Some(b) = &backup {
        manifest["diff"] = json!(changes);
        if let Err(e) = finish_backup(b, sys, manifest.clone()) {
            plog(&format!("warning: could not record backup manifest: {e}"));
        }
        ev(json!({ "event": "diff", "changes": changes }));
        if changes.is_empty() {
            plog("flake.lock unchanged.");
        }
    }

    if !steps.iter().any(|s| s == "rebuild") {
        ev(json!({ "event": "done", "ok": true, "message": "Flake updated (not rebuilt yet)", "rebuildOk": null,
                   "backupId": backup.as_ref().filter(|_| !changes.is_empty()).map(|b| b.id.clone()), "diff": changes }));
        return 0;
    }

    // ---- rebuild: validate → dry-build (cancellable) → switch → post-validate.
    ev(json!({ "event": "step", "id": "rebuild", "status": "running" }));
    let gen_before = common::current_system_generation();
    let target = format!("{}#{}", sys.flake_path, sys.flake_attr);
    let work = Path::new(&sys.state_dir).join("build");
    let _ = fs::create_dir_all(&work);

    // Validate: cheap flake metadata check (not a full `flake check`, which can
    // fail on impure workstation flakes). Still catches a broken flake path.
    ev(json!({ "event": "phase", "text": "Validating flake…", "cancellable": true }));
    plog(&format!("flake: {target}  · generation before: {}", gen_before.map(|g| g.to_string()).unwrap_or_else(|| "?".into())));
    {
        let (ok, c, tail) = stream(
            "nix",
            &["flake", "metadata", "--json", "--no-write-lock-file", &sys.flake_path],
            None,
            true,
            cancel,
            &mut sink,
        );
        if !ok {
            ev(json!({ "event": "step", "id": "rebuild", "status": if c { "cancelled" } else { "failed" } }));
            let err = tail.iter().rev().find(|l| l.contains("error")).cloned().unwrap_or_default();
            return fail(
                if c {
                    "Validation cancelled — the current system was kept".into()
                } else {
                    format!("Flake validation failed — the current system was kept. {err}")
                },
                &backup,
                &changes,
            );
        }
    }

    ev(json!({ "event": "phase", "text": "Dry-build (nixos-rebuild build)…", "cancellable": true }));
    let (ok, c, tail) = stream("nixos-rebuild", &["build", "--flake", &target], Some(&work), true, cancel, &mut sink);
    if !ok {
        ev(json!({ "event": "step", "id": "rebuild", "status": if c { "cancelled" } else { "failed" } }));
        let err = tail.iter().rev().find(|l| l.contains("error")).cloned().unwrap_or_default();
        return fail(
            if c { "Dry-build cancelled — the current system was kept".into() } else { format!("NixOS dry-build failed — the current system was kept. {err}") },
            &backup, &changes);
    }
    let built = fs::canonicalize(work.join("result")).ok();
    let new_kernel = built.as_ref().and_then(|p| {
        let k = fs::read_link(p.join("kernel")).ok()?;
        let n = k.parent()?.file_name()?.to_string_lossy().into_owned();
        n.split_once("-linux-").map(|(_, v)| v.to_string())
    });
    let running = fs::read_to_string("/proc/sys/kernel/osrelease").unwrap_or_default().trim().to_string();
    plog(&format!("Dry-build OK → {}", built.as_ref().map(|p| p.display().to_string()).unwrap_or_default()));

    ev(json!({ "event": "phase", "text": "Activating new configuration (switch)…", "cancellable": false }));
    plog("Activation cannot be cancelled safely; waiting for nixos-rebuild switch to finish.");
    let never = || false;
    let (ok, _, tail) = stream("nixos-rebuild", &["switch", "--flake", &target], Some(&work), false, &never, &mut sink);
    if !ok {
        ev(json!({ "event": "step", "id": "rebuild", "status": "failed" }));
        let err = tail.iter().rev().find(|l| l.contains("error") || l.contains("failed")).cloned().unwrap_or_default();
        return fail(format!("Activation failed. {err}"), &backup, &changes);
    }

    // Post-validate: confirm the profile moved forward.
    ev(json!({ "event": "phase", "text": "Post-validate…", "cancellable": false }));
    let gen_after = common::current_system_generation();
    match (gen_before, gen_after) {
        (Some(b), Some(a)) if a > b => plog(&format!("Post-validate OK — generation {b} → {a}")),
        (Some(b), Some(a)) if a == b => plog(&format!("Post-validate: generation still {a} (switch may have rebuilt in place)")),
        (b, a) => plog(&format!("Post-validate: generation before={b:?} after={a:?}")),
    }

    ev(json!({ "event": "step", "id": "rebuild", "status": "ok" }));
    let reboot = new_kernel.as_deref().is_some_and(|k| k != running);
    let msg = if reboot {
        format!(
            "NixOS update successful (gen {} → {}) — reboot required to use kernel {}",
            gen_before.map(|g| g.to_string()).unwrap_or_else(|| "?".into()),
            gen_after.map(|g| g.to_string()).unwrap_or_else(|| "?".into()),
            new_kernel.clone().unwrap_or_default()
        )
    } else {
        format!(
            "NixOS update successful (generation {} → {})",
            gen_before.map(|g| g.to_string()).unwrap_or_else(|| "?".into()),
            gen_after.map(|g| g.to_string()).unwrap_or_else(|| "?".into())
        )
    };
    ev(json!({
        "event": "done", "ok": true,
        "message": msg,
        "rebuildOk": true, "rebootRequired": reboot, "newKernel": new_kernel,
        "generationBefore": gen_before, "generationAfter": gen_after,
        "backupId": backup.as_ref().filter(|_| !changes.is_empty()).map(|b| b.id.clone()), "diff": changes,
    }));
    0
}

fn revert(sys: &crate::SystemInfo, id: &str) -> i32 {
    let dir = backup_root(sys).join(id);
    let flake = Path::new(&sys.flake_path);
    let Some(manifest) = common::read_json(&dir.join("manifest.json")) else {
        ev(json!({ "event": "done", "ok": false, "message": format!("backup {id} not found") }));
        return 1;
    };
    let mut restored = vec![];
    let mut refused = vec![];
    for f in ["flake.lock", "flake.nix"] {
        let cur_path = flake.join(f);
        let cur = fs::read(&cur_path).unwrap_or_default();
        let before = fs::read(dir.join("before").join(f)).unwrap_or_default();
        let after = fs::read(dir.join("after").join(f)).unwrap_or_default();
        if cur == before {
            continue;
        }
        let meta = fs::metadata(&cur_path).ok();
        if cur == after {
            if common::write_atomic(&cur_path, &before, 0o644).is_ok() {
                restored.push(f);
            }
        } else if f == "flake.nix" {
            // flake.nix was edited since; undo only our one-line URL change.
            let from = manifest["nixpkgsUrl"]["from"].as_str().unwrap_or("");
            let to = manifest["nixpkgsUrl"]["to"].as_str().unwrap_or("");
            let text = String::from_utf8_lossy(&cur).into_owned();
            if !to.is_empty() && text.matches(to).count() == 1 {
                if common::write_atomic(&cur_path, text.replacen(to, from, 1).as_bytes(), 0o644).is_ok() {
                    restored.push("flake.nix (nixpkgs URL only)");
                }
            } else {
                refused.push("flake.nix was changed since the update; left as is");
            }
        } else {
            refused.push("flake.lock was changed since the update; left as is");
        }
        if let Some(m) = meta { restore_owner(&cur_path, m.uid(), m.gid(), m.mode()); }
    }
    for r in &restored { plog(&format!("restored {r}")); }
    for r in &refused { plog(r); }
    let ok = refused.is_empty();
    ev(json!({ "event": "done", "ok": ok,
        "message": if restored.is_empty() && refused.is_empty() { "Nothing to revert — flake files already match the backup".to_string() }
                   else if ok { format!("Reverted {}. Rebuild to return the system to the previous inputs.", restored.join(", ")) }
                   else { format!("Partially reverted: {}", refused.join("; ")) } }));
    if ok { 0 } else { 1 }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn valid_release_accepts_channel_style_names() {
        assert!(valid_release("nixos-26.05.1234.abcdef123456"));
        assert!(valid_release("nixos-26.11pre1077996.6774f7bc2537"));
        assert!(!valid_release("unstable"));
        assert!(!valid_release("nixos-"));
        assert!(!valid_release("nixos-../evil"));
        assert!(!valid_release(&format!("nixos-{}", "a".repeat(80))));
    }

    #[test]
    fn valid_ident_rejects_path_injection() {
        assert!(valid_ident("homeConfigurations"));
        assert!(valid_ident("zionsec"));
        assert!(valid_ident("home-manager"));
        assert!(!valid_ident(""));
        assert!(!valid_ident("../etc"));
        assert!(!valid_ident("foo bar"));
        assert!(!valid_ident(&"x".repeat(64)));
    }

    #[test]
    fn chrono_like_formats_known_unix_instant() {
        // 2026-09-22 22:02:39 UTC
        assert_eq!(chrono_like(1_790_114_559), "20260922T220239Z");
    }

    #[test]
    fn plan_builds_steps_from_status_snapshot() {
        let st = json!({
            "checkedAt": 100,
            "flatpak": {
                "user": { "updates": [{ "ref": "app/com.example.App/x86_64/stable" }] },
                "system": { "updates": [] }
            },
            "mods": { "mods": [
                { "id": "foo", "updateAvailable": true },
                { "id": "bar", "updateAvailable": false }
            ]},
            "nixpkgs": { "updateAvailable": true, "current": "nixos-26.05.1.aaa", "latest": "nixos-26.05.2.bbb" },
            "flakeInputs": [
                { "name": "home-manager", "outdated": true, "newerUpstream": true, "updatableByLock": true },
                { "name": "ambxst", "outdated": false, "newerUpstream": true, "updatableByLock": false, "pin": "commit" },
                { "name": "nixpkgs", "outdated": false, "newerUpstream": true, "updatableByLock": false, "pin": "release" }
            ],
            "flakeRepo": { "git": true, "unrelatedChanges": ["README.md"] },
            "kernel": { "updateChangesKernel": false },
            "ambxst": { "updateAvailable": false }
        });
        let p = plan(&st);
        let ids: Vec<&str> = p["steps"].as_array().unwrap().iter().map(|s| s["id"].as_str().unwrap()).collect();
        assert_eq!(ids, vec!["flatpak-user", "mods", "nixpkgs", "flake-inputs", "rebuild"]);
        assert_eq!(p["steps"][2]["release"], "nixos-26.05.2.bbb");
        assert_eq!(p["steps"][3]["inputs"], json!(["home-manager"]));
        // rebuild is default when flake changes are planned
        assert_eq!(p["steps"][4]["default"], true);
        let warnings = p["warnings"].as_array().unwrap();
        assert!(warnings.iter().any(|w| w.as_str().unwrap().contains("Pinned inputs")));
        assert!(warnings.iter().any(|w| w.as_str().unwrap().contains("uncommitted")));
    }

    #[test]
    fn plan_rebuild_default_false_without_flake_changes() {
        let st = json!({
            "checkedAt": 1,
            "flatpak": { "user": { "updates": [] }, "system": { "updates": [] } },
            "mods": { "mods": [] },
            "nixpkgs": { "updateAvailable": false },
            "flakeInputs": [],
            "flakeRepo": { "git": true, "unrelatedChanges": [] },
            "kernel": { "updateChangesKernel": false },
            "ambxst": { "updateAvailable": false }
        });
        let p = plan(&st);
        let rebuild = p["steps"].as_array().unwrap().iter().find(|s| s["id"] == "rebuild").unwrap();
        assert_eq!(rebuild["default"], false);
    }

    #[test]
    fn lock_diff_reports_changed_inputs_only() {
        use std::io::Write;
        let dir = std::env::temp_dir().join(format!("nixos-updater-lock-diff-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let before = dir.join("before.json");
        let after = dir.join("after.json");
        let mk = |path: &std::path::Path, rev: &str| {
            let mut f = fs::File::create(path).unwrap();
            write!(f, r#"{{"root":"root","nodes":{{"root":{{"inputs":{{"nixpkgs":"nixpkgs"}}}},"nixpkgs":{{"locked":{{"rev":"{rev}"}}}}}}}}"#).unwrap();
        };
        mk(&before, "aaaa");
        mk(&after, "bbbb");
        let diff = lock_diff(&before, &after);
        assert_eq!(diff.len(), 1);
        assert_eq!(diff[0]["input"], "nixpkgs");
        assert_eq!(diff[0]["from"], "aaaa");
        assert_eq!(diff[0]["to"], "bbbb");
        let _ = fs::remove_dir_all(&dir);
    }
}
