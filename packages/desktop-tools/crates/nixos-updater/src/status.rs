//! Read-only status collection. Nothing in this module mutates the system:
//! local facts come from /run, /nix/var/nix/profiles and flake.lock; upstream
//! facts come from `git ls-remote`, HTTP HEAD requests and `flatpak
//! remote-ls --updates`, and are only fetched on an explicit refresh (or a
//! due timer check). Everything is merged into one JSON document that both
//! the widget and the app read.

use crate::{common, Config, SystemInfo, APP};
use serde_json::{json, Value};
use std::fs;
use std::path::Path;
use std::time::Duration;

fn t(cfg: &Config) -> Duration {
    Duration::from_secs(cfg.checks.network_timeout_seconds.clamp(3, 120))
}

fn link_target(p: &str) -> Option<String> {
    fs::read_link(p).ok().map(|x| x.to_string_lossy().into_owned())
}

fn canon(p: &str) -> Option<String> {
    fs::canonicalize(p).ok().map(|x| x.to_string_lossy().into_owned())
}

/// "…-linux-7.2.5/bzImage" -> "7.2.5"
fn kernel_version_of(system: &str) -> Option<String> {
    let k = link_target(&format!("{system}/kernel"))?;
    let name = Path::new(&k).parent()?.file_name()?.to_string_lossy().into_owned();
    let v = name.split_once("-linux-").map(|(_, v)| v.to_string())?;
    Some(v)
}

fn short(rev: &str) -> String {
    rev.chars().take(12).collect()
}

// ---------------------------------------------------------------- local

fn system_section() -> Value {
    let current = canon("/run/current-system").unwrap_or_default();
    let booted = canon("/run/booted-system").unwrap_or_default();
    let profile_link = link_target("/nix/var/nix/profiles/system").unwrap_or_default();
    let generation: Option<u64> = profile_link
        .strip_prefix("system-")
        .and_then(|s| s.strip_suffix("-link"))
        .and_then(|s| s.parse().ok());
    let profile_target = canon("/nix/var/nix/profiles/system").unwrap_or_default();
    let gen_date = fs::symlink_metadata(format!("/nix/var/nix/profiles/{profile_link}"))
        .map(|m| common::mtime_unix(&m))
        .unwrap_or(0);
    let mut gens: Vec<u64> = fs::read_dir("/nix/var/nix/profiles")
        .map(|rd| {
            rd.flatten()
                .filter_map(|e| {
                    let n = e.file_name().to_string_lossy().into_owned();
                    n.strip_prefix("system-")?.strip_suffix("-link")?.parse().ok()
                })
                .collect()
        })
        .unwrap_or_default();
    gens.sort_unstable();

    // NixOS's own "reboot needed" criterion: the booted and current systems
    // differ in kernel, initrd or kernel modules.
    let parts = ["kernel", "initrd", "kernel-modules"];
    let differs: Vec<&str> = parts
        .iter()
        .copied()
        .filter(|p| canon(&format!("/run/booted-system/{p}")) != canon(&format!("/run/current-system/{p}")))
        .collect();
    let reboot = !booted.is_empty() && !current.is_empty() && !differs.is_empty();
    // A generation that is installed as the boot default but not activated
    // (nixos-rebuild boot) also needs a reboot to take effect.
    let pending_boot = !profile_target.is_empty() && profile_target != current;

    json!({
        "hostname": fs::read_to_string("/proc/sys/kernel/hostname").unwrap_or_default().trim(),
        "nixosVersion": fs::read_to_string("/run/current-system/nixos-version").unwrap_or_default().trim(),
        "generation": generation,
        "generationDate": gen_date,
        "generationCount": gens.len(),
        "oldestGeneration": gens.first(),
        "currentSystem": current,
        "bootedSystem": booted,
        "profileSystem": profile_target,
        "currentIsBooted": current == booted,
        "pendingBootGeneration": pending_boot,
        "rebootRecommended": reboot || pending_boot,
        "rebootReason": if reboot {
            format!("Booted system differs from current system ({})", differs.join(", "))
        } else if pending_boot {
            "A newer generation is set as the boot default but is not active".to_string()
        } else { String::new() },
    })
}

fn kernel_section(sys: &SystemInfo) -> Value {
    let running = fs::read_to_string("/proc/sys/kernel/osrelease").unwrap_or_default().trim().to_string();
    let booted = kernel_version_of("/run/booted-system");
    let configured = kernel_version_of("/run/current-system");
    let next_boot = kernel_version_of("/nix/var/nix/profiles/system");
    json!({
        "running": running,
        "booted": booted,
        // Kernel of the active (switched-to) configuration.
        "configured": configured,
        // Kernel the boot default generation will start.
        "nextBoot": next_boot,
        "attr": sys.kernel_attr,
        "branch": sys.kernel_branch,
        "rebootRequired": configured.as_deref().map(|c| c != running).unwrap_or(false)
            || next_boot.as_deref().map(|c| c != running).unwrap_or(false),
    })
}

/// Classify each root flake input from flake.lock: how it is pinned decides
/// whether `nix flake update` can move it at all.
fn flake_inputs_local(sys: &SystemInfo) -> (Vec<Value>, Option<String>) {
    let path = Path::new(&sys.flake_path).join("flake.lock");
    let Some(lock) = common::read_json(&path) else {
        return (vec![], Some(format!("cannot read {}", path.display())));
    };
    let nodes = &lock["nodes"];
    let root = lock["root"].as_str().unwrap_or("root");
    let mut out = vec![];
    if let Some(inputs) = nodes[root]["inputs"].as_object() {
        for (name, node_ref) in inputs {
            // Follows are arrays; only direct inputs are listed.
            let Some(node_name) = node_ref.as_str() else { continue };
            let node = &nodes[node_name];
            let locked = &node["locked"];
            let original = &node["original"];
            let typ = locked["type"].as_str().unwrap_or("?");
            let pin = if typ == "tarball" || typ == "file" {
                "release"
            } else if original.get("rev").is_some() {
                "commit"
            } else if let Some(r) = original["ref"].as_str() {
                if r.starts_with('v') || r.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false) {
                    "tag"
                } else {
                    "branch"
                }
            } else {
                "branch"
            };
            out.push(json!({
                "name": name,
                "type": typ,
                "pin": pin,
                "owner": locked["owner"],
                "repo": locked["repo"],
                "url": locked["url"],
                "ref": original["ref"],
                "rev": locked["rev"],
                "shortRev": locked["rev"].as_str().map(short),
                "lastModified": locked["lastModified"],
                // Only branch-following inputs move with `nix flake update`.
                "updatableByLock": pin == "branch",
            }));
        }
    }
    (out, None)
}

/// Is the flake directory a git repo, and are there changes other than ours?
fn flake_repo(sys: &SystemInfo) -> Value {
    let p = Path::new(&sys.flake_path);
    if !p.join(".git").exists() {
        return json!({
            "path": sys.flake_path, "git": false, "unrelatedChanges": [],
            "note": "Not a Git repository. Before flake.nix/flake.lock are modified, the originals are backed up under /var/lib/nixos-updater/backups and can be restored from the app.",
        });
    }
    let r = common::run("git", &["-C", &sys.flake_path, "status", "--porcelain"], Duration::from_secs(10));
    let changes: Vec<String> = r
        .stdout
        .lines()
        .map(|l| l.get(3..).unwrap_or("").to_string())
        .filter(|f| f != "flake.lock" && f != "flake.nix")
        .collect();
    json!({
        "path": sys.flake_path, "git": true, "unrelatedChanges": changes,
        "note": if changes.is_empty() { "Working tree clean apart from flake files." } else {
            "Uncommitted changes exist. They are left untouched; only flake.nix/flake.lock are modified." },
    })
}

fn ambxst_local(sys: &SystemInfo) -> Value {
    if !common::have("ambxst") {
        return json!({ "available": false });
    }
    let v = common::run("ambxst", &["--version"], Duration::from_secs(5));
    let version = v.stdout.trim().trim_start_matches("Ambxst").trim().to_string();
    let pinned = fs::read_to_string(&sys.ambxst_pin_file).ok().and_then(|s| {
        let i = s.find("github:Axenide/Ambxst/")? + "github:Axenide/Ambxst/".len();
        Some(s[i..].chars().take_while(|c| c.is_ascii_hexdigit()).collect::<String>())
    });
    json!({
        "available": true,
        "version": version,
        "pinnedRev": pinned,
        "pinFile": sys.ambxst_pin_file,
        "managedBy": "NixOS module (pinned flake revision)",
        "note": "Ambxst is pinned declaratively. `ambxst update` installs through `nix profile` and would conflict with the pin, so updating means bumping the revision in the pin file and rebuilding.",
    })
}

fn mods_local() -> Value {
    if !common::have("ambxst") {
        return json!({ "available": false, "mods": [] });
    }
    let r = common::run("ambxst", &["mods", "list"], Duration::from_secs(10));
    if !r.ok {
        return json!({ "available": false, "mods": [], "error": r.stderr.trim() });
    }
    let mut generation = String::new();
    let mut mods = vec![];
    // Sources are only read (never written) from Ambxst's own state file so
    // local-source mods can be compared with their source manifest.
    let state = common::read_json(&common::config_dir("ambxst").join("mods.json"));
    for line in r.stdout.lines() {
        if let Some(g) = line.strip_prefix("Active generation:") {
            generation = g.trim().to_string();
            continue;
        }
        let f: Vec<&str> = line.split_whitespace().collect();
        if f.len() >= 3 && (f[0] == "enabled" || f[0] == "disabled") {
            let id = f[1];
            let version = f[2];
            let entry = state
                .as_ref()
                .and_then(|s| s["mods"].as_array())
                .and_then(|a| a.iter().find(|m| m["id"] == id))
                .cloned()
                .unwrap_or(Value::Null);
            let source = entry["source"].as_str().unwrap_or("").to_string();
            let source_type = entry["sourceType"].as_str().unwrap_or("").to_string();
            let source_version = if source_type == "local" {
                common::read_json(&Path::new(&source).join("ambxst.mod.json"))
                    .and_then(|m| m["version"].as_str().map(String::from))
            } else {
                None
            };
            let update = source_version.as_deref().map(|sv| sv != version);
            mods.push(json!({
                "id": id, "enabled": f[0] == "enabled", "version": version,
                "source": source, "sourceType": source_type,
                "sourceVersion": source_version,
                // null = unknown without fetching (git sources); use Update Mods.
                "updateAvailable": update,
            }));
        }
    }
    let count = mods.iter().filter(|m| m["updateAvailable"] == true).count();
    json!({ "available": true, "activeGeneration": generation, "mods": mods, "updateCount": count })
}

// ---------------------------------------------------------------- network

/// Latest release of the channel a releases.nixos.org URL came from, by
/// following channels.nixos.org's redirect (a HEAD request, no download).
fn nixpkgs_latest(url: &str, cfg: &Config) -> Value {
    // https://releases.nixos.org/nixos/unstable/nixos-26.11pre1073009.ef34387ddd75/nixexprs.tar.xz
    let parts: Vec<&str> = url.trim_start_matches("https://releases.nixos.org/").split('/').collect();
    if parts.len() < 3 || !url.starts_with("https://releases.nixos.org/") {
        return json!({ "error": "nixpkgs is not pinned to a releases.nixos.org channel release" });
    }
    let (series, release) = (parts[1], parts[2]);
    let channel = if series == "unstable" { "nixos-unstable".to_string() } else { format!("nixos-{series}") };
    let r = common::run(
        "curl",
        &["-sS", "-I", "--max-time", &t(cfg).as_secs().to_string(), &format!("https://channels.nixos.org/{channel}")],
        t(cfg) + Duration::from_secs(2),
    );
    let loc = r
        .stdout
        .lines()
        .find_map(|l| l.to_ascii_lowercase().starts_with("location:").then(|| l[9..].trim().to_string()));
    let Some(loc) = loc else {
        return json!({ "channel": channel, "current": release, "error": format!("channel lookup failed: {}", r.stderr.trim()) });
    };
    let latest = loc.trim_end_matches('/').rsplit('/').next().unwrap_or("").to_string();
    let rev_of = |rel: &str| rel.rsplit('.').next().unwrap_or("").to_string();
    json!({
        "channel": channel,
        "current": release,
        "currentRev": rev_of(release),
        "latest": latest,
        "latestRev": rev_of(&latest),
        "latestUrl": format!("https://releases.nixos.org/nixos/{series}/{latest}/nixexprs.tar.xz"),
        "updateAvailable": !latest.is_empty() && latest != release,
    })
}

/// Kernel version the given nixpkgs release would provide for our branch,
/// from nixpkgs' kernels-org.json at the release's exact git revision.
fn kernel_lookahead(release_dir: &str, branch: &str, cfg: &Config) -> Option<String> {
    let secs = t(cfg).as_secs().to_string();
    let rev = common::run("curl", &["-fsS", "--max-time", &secs, &format!("{release_dir}/git-revision")], t(cfg) + Duration::from_secs(2));
    let rev = rev.stdout.trim().to_string();
    if !rev.chars().all(|c| c.is_ascii_hexdigit()) || rev.len() < 12 {
        return None;
    }
    let j = common::run(
        "curl",
        &["-fsS", "--max-time", &secs,
          &format!("https://raw.githubusercontent.com/NixOS/nixpkgs/{rev}/pkgs/os-specific/linux/kernel/kernels-org.json")],
        t(cfg) + Duration::from_secs(2),
    );
    let v: Value = serde_json::from_str(&j.stdout).ok()?;
    v[branch]["version"].as_str().map(String::from)
}

/// `git ls-remote [--tags] <url> [patterns…]` — options must precede the URL.
fn ls_remote(url: &str, args: &[&str], cfg: &Config) -> Result<Vec<(String, String)>, String> {
    let mut a = vec!["ls-remote"];
    let (opts, pats): (Vec<&str>, Vec<&str>) = args.iter().partition(|x| x.starts_with("--"));
    a.extend(opts);
    a.push(url);
    a.extend(pats);
    let r = common::run("git", &a, t(cfg));
    if !r.ok {
        return Err(if r.timed_out { "timed out".into() } else { r.stderr.trim().lines().last().unwrap_or("git ls-remote failed").to_string() });
    }
    Ok(r.stdout
        .lines()
        .filter_map(|l| l.split_once('\t').map(|(a, b)| (a.to_string(), b.to_string())))
        .collect())
}

fn version_key(tag: &str) -> Vec<u64> {
    tag.trim_start_matches('v').split(|c: char| !c.is_ascii_digit()).filter_map(|s| s.parse().ok()).collect()
}

fn latest_tag(refs: &[(String, String)]) -> Option<(String, String)> {
    // Prefer peeled (^{}) commits for annotated tags.
    let mut tags: Vec<(String, String)> = vec![];
    for (sha, r) in refs {
        let Some(name) = r.strip_prefix("refs/tags/") else { continue };
        let (name, peeled) = match name.strip_suffix("^{}") { Some(n) => (n, true), None => (name, false) };
        if !name.chars().any(|c| c.is_ascii_digit()) {
            continue;
        }
        if let Some(e) = tags.iter_mut().find(|(n, _)| n == name) {
            if peeled { e.1 = sha.clone(); }
        } else {
            tags.push((name.to_string(), sha.clone()));
        }
    }
    tags.into_iter().max_by(|a, b| version_key(&a.0).cmp(&version_key(&b.0)))
}

fn github_upstream(input: &mut Value, cfg: &Config) {
    let (Some(owner), Some(repo)) = (input["owner"].as_str(), input["repo"].as_str()) else { return };
    let url = format!("https://github.com/{owner}/{repo}");
    let rev = input["rev"].as_str().unwrap_or("").to_string();
    match input["pin"].as_str() {
        Some("tag") => match ls_remote(&url, &["--tags"], cfg) {
            Ok(refs) => {
                if let Some((tag, sha)) = latest_tag(&refs) {
                    let newer = Some(tag.as_str()) != input["ref"].as_str();
                    input["latest"] = json!({ "tag": tag, "rev": sha, "shortRev": short(&sha) });
                    input["newerUpstream"] = json!(newer);
                }
            }
            Err(e) => input["error"] = json!(e),
        },
        _ => {
            let args: Vec<&str> = match input["ref"].as_str() {
                Some(r) if input["pin"] == "branch" => vec![r],
                _ => vec!["HEAD"],
            };
            match ls_remote(&url, &args, cfg) {
                Ok(refs) => {
                    if let Some((sha, _)) = refs.first() {
                        input["latest"] = json!({ "rev": sha, "shortRev": short(sha) });
                        input["newerUpstream"] = json!(*sha != rev);
                    }
                }
                Err(e) => input["error"] = json!(e),
            }
        }
    }
    // Only branch inputs are actionable by a lock update; pinned ones need an
    // intentional edit of flake.nix and are reported, not counted.
    let outdated = input["updatableByLock"] == true && input["newerUpstream"] == true;
    input["outdated"] = json!(outdated);
}

fn flatpak_scope(scope: &str, cfg: &Config) -> Value {
    let flag = format!("--{scope}");
    let installed = common::run("flatpak", &["list", &flag, "--columns=application"], Duration::from_secs(20));
    let n_installed = installed.stdout.lines().filter(|l| !l.trim().is_empty()).count();
    let r = common::run(
        "flatpak",
        &["remote-ls", "--updates", &flag, "--columns=ref,version,download-size"],
        t(cfg) + Duration::from_secs(20),
    );
    if !r.ok {
        return json!({ "installed": n_installed, "updates": [], "error": r.stderr.trim() });
    }
    let updates: Vec<Value> = r
        .stdout
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| {
            let f: Vec<&str> = l.split('\t').collect();
            json!({ "ref": f.first().unwrap_or(&"").trim(), "version": f.get(1).unwrap_or(&"").trim(), "downloadSize": f.get(2).unwrap_or(&"").trim() })
        })
        .collect();
    json!({ "installed": n_installed, "updates": updates })
}

fn ambxst_upstream(cfg: &Config) -> Value {
    let url = "https://github.com/Axenide/Ambxst";
    let head = ls_remote(url, &["HEAD"], cfg);
    let tags = ls_remote(url, &["--tags"], cfg);
    let mut v = json!({});
    match head {
        Ok(r) => { if let Some((sha, _)) = r.first() { v["upstreamRev"] = json!(sha); } }
        Err(e) => v["error"] = json!(e),
    }
    if let Ok(r) = tags {
        if let Some((tag, sha)) = latest_tag(&r) {
            v["latestTag"] = json!(tag);
            v["latestTagRev"] = json!(sha);
        }
    }
    v
}

// ---------------------------------------------------------------- merge

fn merge(dst: &mut Value, src: &Value) {
    if let (Some(d), Some(s)) = (dst.as_object_mut(), src.as_object()) {
        for (k, v) in s {
            d.insert(k.clone(), v.clone());
        }
    }
}

/// Collect status. Without `refresh`, upstream facts are taken from the cache
/// (marked with the time they were fetched) and no network access happens.
pub fn collect(cfg: &Config, cfg_err: Option<String>, refresh: bool) -> Value {
    let sys = crate::system_info();
    let cached = common::read_json(&crate::cache_file()).unwrap_or(Value::Null);
    let mut errors: Vec<String> = cfg_err.into_iter().collect();

    let system = system_section();
    let kernel = if cfg.checks.kernel { kernel_section(&sys) } else { json!({ "hidden": true }) };
    let (mut inputs, lock_err) = flake_inputs_local(&sys);
    errors.extend(lock_err);
    let mut ambxst = if cfg.checks.ambxst { ambxst_local(&sys) } else { json!({ "hidden": true }) };
    let mods = if cfg.checks.ambxst { mods_local() } else { json!({ "hidden": true }) };

    let checked_at;
    let mut nixpkgs;
    let mut flatpak;
    let mut offline = false;
    if refresh {
        checked_at = common::now_unix();
        for i in inputs.iter_mut() {
            if i["type"] == "github" {
                github_upstream(i, cfg);
            }
        }
        let np_url = inputs.iter().find(|i| i["name"] == "nixpkgs").and_then(|i| i["url"].as_str()).unwrap_or("").to_string();
        nixpkgs = nixpkgs_latest(&np_url, cfg);
        if cfg.checks.kernel && cfg.checks.kernel_lookahead && nixpkgs["updateAvailable"] == true && !sys.kernel_branch.is_empty() {
            let url = nixpkgs["latestUrl"].as_str().unwrap_or("");
            let dir = url.trim_end_matches("/nixexprs.tar.xz");
            nixpkgs["kernelAfterUpdate"] = json!(kernel_lookahead(dir, &sys.kernel_branch, cfg));
        }
        offline = nixpkgs.get("error").is_some() && inputs.iter().all(|i| i.get("error").is_some() || i["type"] != "github");
        flatpak = if cfg.checks.flatpak && common::have("flatpak") {
            json!({ "available": true, "user": flatpak_scope("user", cfg), "system": flatpak_scope("system", cfg) })
        } else {
            json!({ "available": false, "hidden": !cfg.checks.flatpak })
        };
        if cfg.checks.ambxst && ambxst["available"] == true {
            let up = ambxst_upstream(cfg);
            merge(&mut ambxst, &up);
        }
    } else {
        checked_at = cached["checkedAt"].as_i64().unwrap_or(0);
        nixpkgs = cached["nixpkgs"].clone();
        if nixpkgs.is_null() { nixpkgs = json!({}); }
        // The lock may have changed since the cache was written.
        let np_url = inputs.iter().find(|i| i["name"] == "nixpkgs").and_then(|i| i["url"].as_str()).unwrap_or("");
        if let Some(rel) = np_url.split('/').rev().nth(1) {
            if nixpkgs["current"].as_str().is_some_and(|c| c != rel) {
                nixpkgs["current"] = json!(rel);
                nixpkgs["updateAvailable"] = json!(nixpkgs["latest"].as_str() != Some(rel));
            }
        }
        for i in inputs.iter_mut() {
            if let Some(ci) = cached["flakeInputs"].as_array().and_then(|a| a.iter().find(|c| c["name"] == i["name"])) {
                if ci["rev"] == i["rev"] {
                    for k in ["latest", "newerUpstream", "outdated", "error"] {
                        if let Some(v) = ci.get(k) { i[k] = v.clone(); }
                    }
                }
            }
        }
        flatpak = cached["flatpak"].clone();
        if flatpak.is_null() || !cfg.checks.flatpak { flatpak = json!({ "available": false, "hidden": !cfg.checks.flatpak }); }
        if cfg.checks.ambxst {
            for k in ["upstreamRev", "latestTag", "latestTagRev", "error"] {
                if let Some(v) = cached["ambxst"].get(k) { ambxst[k] = v.clone(); }
            }
        }
    }

    // Ambxst update = newer upstream tag than the running version.
    if let (Some(ver), Some(tag)) = (ambxst["version"].as_str(), ambxst["latestTag"].as_str()) {
        ambxst["updateAvailable"] = json!(version_key(tag) > version_key(ver));
    }

    let kernel_next = nixpkgs["kernelAfterUpdate"].as_str().map(String::from);
    let mut kernel = kernel;
    if kernel.get("hidden").is_none() {
        kernel["availableAfterUpdate"] = json!(kernel_next.clone().or_else(|| kernel["configured"].as_str().map(String::from)));
        kernel["updateChangesKernel"] = json!(kernel_next.is_some() && kernel_next.as_deref() != kernel["configured"].as_str());
    }

    // Actionable update count — only things the app can actually update.
    let fp_user = flatpak["user"]["updates"].as_array().map(|a| a.len()).unwrap_or(0);
    let fp_sys = flatpak["system"]["updates"].as_array().map(|a| a.len()).unwrap_or(0);
    let np = (nixpkgs["updateAvailable"] == true) as usize;
    let inputs_outdated = inputs.iter().filter(|i| i["outdated"] == true).count();
    let pinned_newer = inputs.iter().filter(|i| i["newerUpstream"] == true && i["updatableByLock"] != true && i["name"] != "nixpkgs").count();
    let mods_updates = mods["updateCount"].as_u64().unwrap_or(0) as usize;
    let count = fp_user + fp_sys + np + inputs_outdated + mods_updates;

    let reboot = system["rebootRecommended"] == true || kernel["rebootRequired"] == true;
    let last_run = common::read_json(&common::state_dir(APP).join("last-run.json")).unwrap_or(Value::Null);
    let pending_revert = common::read_json(&common::state_dir(APP).join("pending-revert.json")).unwrap_or(Value::Null);

    let state = if checked_at == 0 {
        "unknown"
    } else if offline {
        "error"
    } else if count > 0 {
        "updates"
    } else if reboot {
        "reboot"
    } else {
        "up-to-date"
    };
    let headline = match state {
        "unknown" => "Not checked yet".to_string(),
        "error" => "Update check failed".to_string(),
        "updates" => format!("{count} update{} available", if count == 1 { "" } else { "s" }),
        "reboot" => "Reboot recommended".to_string(),
        _ => "Up to date".to_string(),
    };

    let mut v = json!({
        "schema": 1,
        "checkedAt": checked_at,
        "generatedAt": common::now_unix(),
        "summary": {
            "state": state,
            "headline": headline,
            "updateCount": count,
            "rebootRecommended": reboot,
            "breakdown": {
                "flatpakUser": fp_user, "flatpakSystem": fp_sys, "nixpkgs": np,
                "flakeInputs": inputs_outdated, "pinnedInputsWithNewerUpstream": pinned_newer,
                "mods": mods_updates,
                "ambxst": ambxst["updateAvailable"] == true,
            },
        },
        "system": system,
        "kernel": kernel,
        "nixpkgs": nixpkgs,
        "flakeInputs": inputs,
        "flakeRepo": flake_repo(&sys),
        "flatpak": flatpak,
        "ambxst": ambxst,
        "mods": mods,
        "lastRun": last_run,
        "pendingRevert": pending_revert,
        "errors": errors,
    });
    // Always persist: the widget watches this file. Without --refresh only the
    // local facts are new; checkedAt keeps the time of the last network check.
    {
        if let Err(e) = common::write_json(&crate::cache_file(), &v, 0o600) {
            v["errors"].as_array_mut().unwrap().push(json!(format!("cache write failed: {e}")));
        }
    }
    v
}

/// Timer entry point. Exits quickly unless automatic checks are enabled and
/// the configured interval has elapsed. Notifies only when the set of
/// available updates changed since the last notification.
pub fn scheduled_check(cfg: &Config, cfg_err: Option<String>, scheduled: bool) -> i32 {
    if scheduled && !cfg.checks.automatic {
        return 0;
    }
    let Some(_lock) = common::try_lock(&crate::lock_file()) else { return 0 };
    let cached = common::read_json(&crate::cache_file()).unwrap_or(Value::Null);
    let last = cached["checkedAt"].as_i64().unwrap_or(0);
    let due = common::now_unix() - last >= (cfg.checks.interval_hours.max(1) * 3600) as i64;
    if scheduled && !due {
        return 0;
    }
    let st = collect(cfg, cfg_err, true);
    if cfg.notifications.enabled && cfg.notifications.updates {
        let sig_path = common::state_dir(APP).join("notified.json");
        let count = st["summary"]["updateCount"].as_u64().unwrap_or(0);
        let sig = json!({
            "count": count,
            "nixpkgs": st["nixpkgs"]["latest"],
            "flatpak": [st["flatpak"]["user"]["updates"], st["flatpak"]["system"]["updates"]],
            "inputs": st["flakeInputs"].as_array().map(|a| a.iter().filter(|i| i["outdated"] == true).map(|i| i["latest"].clone()).collect::<Vec<_>>()),
        });
        let prev = common::read_json(&sig_path);
        if count > 0 && prev.as_ref() != Some(&sig) {
            let mut parts = vec![];
            let b = &st["summary"]["breakdown"];
            if b["nixpkgs"].as_u64() == Some(1) { parts.push("nixpkgs".to_string()); }
            let fp = b["flatpakUser"].as_u64().unwrap_or(0) + b["flatpakSystem"].as_u64().unwrap_or(0);
            if fp > 0 { parts.push(format!("{fp} Flatpak")); }
            if b["flakeInputs"].as_u64().unwrap_or(0) > 0 { parts.push(format!("{} flake input(s)", b["flakeInputs"])); }
            if b["mods"].as_u64().unwrap_or(0) > 0 { parts.push(format!("{} mod(s)", b["mods"])); }
            common::notify(
                "NixOS Updater",
                "system-software-update",
                &format!("{count} system update{} available", if count == 1 { "" } else { "s" }),
                &parts.join(" · "),
            );
        }
        let _ = common::write_json(&sig_path, &sig, 0o600);
    }
    0
}
