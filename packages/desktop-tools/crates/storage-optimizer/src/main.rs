//! storage-optimizer-helper — backend shared by the Storage Optimizer app and
//! its Quickshell widget.
//!
//! Read-only:
//!   summary                 filesystem usage + last scan headline (cheap, no walk), JSON
//!   scan                    full analysis; JSON-lines progress, final result cached, cancellable
//!   preview <category>      exactly what a Safe Clean category would remove, JSON
//!   config                  effective configuration, JSON
//!
//! Mutating (explicit UI action + confirmation only):
//!   clean --scan <id> --categories a,b     Safe Clean the selected categories, rescan, report
//!   trash <path>                           move one user-selected item to the Trash (not delete)
//!   ignore <path> / unignore <path>        hide an item from Large Items
//!   privileged clean …                     root half (pkexec): generations, GC, journal

mod clean;
mod scan;

use desktop_tools_common as common;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

pub const APP: &str = "storage-optimizer";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ScanCfg {
    pub steam: bool,
    pub ai_models: bool,
    pub vms: bool,
    pub developer: bool,
    pub containers: bool,
    /// Extra local directories to analyze (network mounts are skipped).
    pub extra_roots: Vec<String>,
    /// Paths never descended into.
    pub exclude: Vec<String>,
    /// Items at least this large appear under Large Items.
    pub large_item_threshold_gb: f64,
    /// When the app opens, rescan automatically if the cached scan is older
    /// than this. 0 = never scan automatically.
    pub rescan_on_open_after_hours: u64,
    pub threads: usize,
}

impl Default for ScanCfg {
    fn default() -> Self {
        Self {
            steam: true,
            ai_models: true,
            vms: true,
            developer: true,
            containers: true,
            extra_roots: vec![],
            exclude: vec![],
            large_item_threshold_gb: 1.0,
            rescan_on_open_after_hours: 0,
            threads: 6,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct CleanDefaults {
    pub nix_generations: bool,
    pub nix_garbage: bool,
    pub flatpak_unused: bool,
    pub trash: bool,
    pub thumbnails: bool,
    pub journal: bool,
    pub package_caches: bool,
    pub containers: bool,
}

impl Default for CleanDefaults {
    fn default() -> Self {
        Self {
            nix_generations: true,
            nix_garbage: true,
            flatpak_unused: true,
            trash: false,
            thumbnails: true,
            journal: true,
            package_caches: false,
            containers: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct CleanCfg {
    /// Newest N system generations are always kept (in addition to the
    /// current, booted and boot-default generations).
    pub keep_system_generations: usize,
    /// Newest N generations of your own Nix profile are kept.
    pub keep_user_generations: usize,
    /// journalctl --vacuum-time value, e.g. "2weeks", "1month".
    pub journal_retention: String,
    pub defaults: CleanDefaults,
}

impl Default for CleanCfg {
    fn default() -> Self {
        Self {
            keep_system_generations: 3,
            keep_user_generations: 1,
            journal_retention: "4weeks".into(),
            defaults: CleanDefaults::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Notif {
    pub enabled: bool,
    /// Notify when a scan finds AI models above this size (GB); 0 = never.
    pub ai_models_over_gb: f64,
}

impl Default for Notif {
    fn default() -> Self {
        Self { enabled: true, ai_models_over_gb: 100.0 }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct WidgetCfg {
    pub enabled: bool,
    /// "percent" (58%) or "free" (748 GB free)
    pub display: String,
}

impl Default for WidgetCfg {
    fn default() -> Self {
        Self { enabled: true, display: "free".into() }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub scan: ScanCfg,
    pub clean: CleanCfg,
    pub notifications: Notif,
    pub widget: WidgetCfg,
}

pub const DEFAULT_CONFIG: &str = r#"# Storage Optimizer configuration.
# Read by storage-optimizer-helper (shared by the app and the Quickshell
# widget). There is no background scanner: scans run only when you ask.

[scan]
steam = true
ai_models = true
vms = true
developer = true
containers = true
# Extra local directories to analyze. Network mounts are always skipped.
extra_roots = []
# Paths that are never scanned.
exclude = []
# Items at least this large are listed under Large Items.
large_item_threshold_gb = 1.0
# Rescan automatically when the app opens and the last scan is older than
# this many hours. 0 = never scan automatically.
rescan_on_open_after_hours = 0
threads = 6

[clean]
# Always kept: the current, booted and boot-default system generations,
# plus the newest N below.
keep_system_generations = 3
keep_user_generations = 1
# journalctl --vacuum-time value.
journal_retention = "4weeks"

# Which Safe Clean categories start selected. You still review and confirm.
[clean.defaults]
nix_generations = true
nix_garbage = true
flatpak_unused = true
trash = false
thumbnails = true
journal = true
package_caches = false
containers = false

[notifications]
enabled = true
# "Storage scan found N GB of AI models" when above this size. 0 = never.
ai_models_over_gb = 100.0

[widget]
enabled = true
# "free" shows "748 GB free"; "percent" shows "58%".
display = "free"
"#;

pub fn scan_file() -> PathBuf {
    common::cache_dir(APP).join("scan.json")
}

pub fn ignore_file() -> PathBuf {
    common::state_dir(APP).join("ignored.json")
}

pub fn lock_file() -> PathBuf {
    let run = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{}", common::uid()));
    PathBuf::from(run).join(APP).join("busy.lock")
}

/// Runtime file announcing what the helper is doing ("scanning"/"cleaning"
/// + phase), so the bar widget can show progress for work started in the app.
/// Written only on phase changes; `activity == ""` means idle.
pub fn activity_file() -> PathBuf {
    let run = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{}", common::uid()));
    PathBuf::from(run).join(APP).join("activity.json")
}

pub fn set_activity(activity: &str, phase: &str) {
    let _ = common::write_json(
        &activity_file(),
        &serde_json::json!({ "activity": activity, "phase": phase, "pid": std::process::id(), "at": common::now_unix() }),
        0o600,
    );
}

/// Make sure the file exists (the widget can only watch an existing file)
/// and clear it if the process that wrote it is gone (e.g. killed mid-run).
pub fn ensure_activity_file() {
    let f = activity_file();
    let stale = match common::read_json(&f) {
        None => true,
        Some(v) => {
            let busy = v["activity"].as_str().is_some_and(|a| !a.is_empty());
            let pid = v["pid"].as_u64().unwrap_or(0);
            busy && !std::path::Path::new(&format!("/proc/{pid}")).exists()
        }
    };
    if stale {
        set_activity("", "");
    }
}

fn usage() -> ! {
    eprintln!("usage: storage-optimizer-helper <summary | scan | preview <category> | config | clean --scan <id> --categories a,b | trash <path> | ignore <path> | unignore <path>>");
    std::process::exit(2)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(cmd) = args.first().map(String::as_str) else { usage() };
    let rest = &args[1..];
    if cmd == "privileged" {
        common::setup_tools_path(true);
        std::process::exit(clean::privileged_main(rest));
    }
    common::setup_tools_path(false);
    common::install_cancel_handler();
    let _ = common::ensure_default_config(APP, DEFAULT_CONFIG);
    let (cfg, cfg_err) = common::load_config::<Config>(APP);

    let code = match cmd {
        "summary" => {
            ensure_activity_file();
            common::emit(&scan::summary(&cfg, cfg_err));
            0
        }
        "scan" => scan::scan_main(&cfg, cfg_err),
        "preview" => {
            let Some(cat) = rest.first() else { usage() };
            common::emit(&clean::preview(&cfg, cat));
            0
        }
        "clean" => clean::clean_main(&cfg, rest),
        "trash" => {
            let Some(p) = rest.first() else { usage() };
            clean::trash_main(&cfg, p)
        }
        "ignore" | "unignore" => {
            let Some(p) = rest.first() else { usage() };
            scan::set_ignored(p, cmd == "ignore")
        }
        "config" => {
            common::emit(&serde_json::json!({
                "config": cfg, "error": cfg_err,
                "path": common::config_dir(APP).join("config.toml"),
            }));
            0
        }
        _ => usage(),
    };
    std::process::exit(code);
}
