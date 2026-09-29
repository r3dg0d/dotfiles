//! nixos-updater-helper — backend shared by the NixOS Updater app and its
//! Quickshell widget.
//!
//! Read-only commands (never mutate the system):
//!   status [--refresh]     local facts + cached (or freshly fetched) upstream state, JSON
//!   plan                   the staged "Update All" plan derived from the last status, JSON
//!   check --scheduled      timer entry point: refresh only if due, notify on change
//!   config                 effective configuration, JSON
//!
//! Mutating commands (only ever run from an explicit UI action):
//!   apply <action> [...]   stream JSON-lines progress while running one action
//!   cancel                 ask a running apply to stop at the next safe point
//!   privileged <action>    root half of apply, reached only through pkexec

mod actions;
mod status;

use desktop_tools_common as common;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

pub const APP: &str = "nixos-updater";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Checks {
    /// Let the systemd user timer run background checks.
    pub automatic: bool,
    /// Minimum hours between background checks (the timer fires hourly and
    /// exits immediately unless a check is due).
    pub interval_hours: u64,
    pub flatpak: bool,
    pub ambxst: bool,
    pub kernel: bool,
    /// Fetch nixpkgs' kernels-org.json (a few KB) to show which kernel a
    /// nixpkgs update would bring. Only happens during a refresh.
    pub kernel_lookahead: bool,
    pub network_timeout_seconds: u64,
}

impl Default for Checks {
    fn default() -> Self {
        Self {
            automatic: true,
            interval_hours: 24,
            flatpak: true,
            ambxst: true,
            kernel: true,
            kernel_lookahead: true,
            network_timeout_seconds: 20,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Notifications {
    pub enabled: bool,
    /// Notify when a background check finds a *new* set of updates.
    pub updates: bool,
    /// Notify when an update/rebuild finishes (success or failure).
    pub results: bool,
}

impl Default for Notifications {
    fn default() -> Self {
        Self { enabled: true, updates: true, results: true }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Widget {
    pub enabled: bool,
    pub show_count: bool,
}

impl Default for Widget {
    fn default() -> Self {
        Self { enabled: true, show_count: true }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub checks: Checks,
    pub notifications: Notifications,
    pub widget: Widget,
}

pub const DEFAULT_CONFIG: &str = r#"# NixOS Updater configuration.
# Read by nixos-updater-helper (the backend shared by the app and the
# Quickshell widget). Changes apply on the next check; no restart needed.

[checks]
# Background checks via the nixos-updater-check.timer user timer.
# The timer fires hourly but exits immediately unless a check is due.
automatic = true
interval_hours = 24
flatpak = true
ambxst = true
kernel = true
# Fetch nixpkgs' kernels-org.json (a few KB) to show which kernel a nixpkgs
# update would bring. Only during a check, never in the background otherwise.
kernel_lookahead = true
network_timeout_seconds = 20

[notifications]
enabled = true
# "N system updates available" — only when the set of updates changes.
updates = true
# Rebuild / update finished or failed.
results = true

[widget]
enabled = true
show_count = true
"#;

/// Facts about the declarative system configuration, written by the NixOS
/// module to /etc/nixos-updater/system.json. Root-owned and immutable, so the
/// privileged half trusts it; it never trusts the user's config for paths.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SystemInfo {
    pub flake_path: String,
    pub flake_attr: String,
    pub kernel_attr: String,
    pub kernel_branch: String,
    pub kernel_version: String,
    pub ambxst_pin_file: String,
    pub state_dir: String,
}

impl Default for SystemInfo {
    fn default() -> Self {
        Self {
            flake_path: "/etc/nixos".into(),
            flake_attr: String::new(),
            kernel_attr: String::new(),
            kernel_branch: String::new(),
            kernel_version: String::new(),
            ambxst_pin_file: String::new(),
            state_dir: "/var/lib/nixos-updater".into(),
        }
    }
}

pub fn system_info() -> SystemInfo {
    common::read_json(std::path::Path::new("/etc/nixos-updater/system.json"))
        .and_then(|v| serde_json::from_value(v).ok())
        .unwrap_or_default()
}

pub fn cache_file() -> PathBuf {
    common::cache_dir(APP).join("status.json")
}

pub fn lock_file() -> PathBuf {
    let run = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{}", common::uid()));
    PathBuf::from(run).join(APP).join("busy.lock")
}

fn usage() -> ! {
    eprintln!(
        "usage: nixos-updater-helper <status [--refresh] | plan | check --scheduled | config | init-config | apply <action> | cancel | privileged <action>>\n\
         actions: flatpak-user flatpak-system mods nixpkgs flake-inputs rebuild update-all revert-lock"
    );
    std::process::exit(2)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(cmd) = args.first().map(String::as_str) else { usage() };
    let rest = &args[1..];

    if cmd == "privileged" {
        common::setup_tools_path(true);
        std::process::exit(actions::privileged_main(rest));
    }
    common::setup_tools_path(false);
    common::install_cancel_handler();
    let _ = common::ensure_default_config(APP, DEFAULT_CONFIG);
    let (cfg, cfg_err) = common::load_config::<Config>(APP);

    match cmd {
        "status" => {
            let refresh = rest.iter().any(|a| a == "--refresh");
            let st = status::collect(&cfg, cfg_err, refresh);
            common::emit(&st);
        }
        "plan" => {
            let st = status::collect(&cfg, cfg_err, false);
            common::emit(&actions::plan(&st));
        }
        "check" => {
            let scheduled = rest.iter().any(|a| a == "--scheduled");
            std::process::exit(status::scheduled_check(&cfg, cfg_err, scheduled));
        }
        "config" => {
            let v = serde_json::json!({
                "config": cfg,
                "error": cfg_err,
                "path": common::config_dir(APP).join("config.toml"),
                "system": system_info(),
            });
            common::emit(&v);
        }
        "init-config" => match common::ensure_default_config(APP, DEFAULT_CONFIG) {
            Ok(p) => println!("{}", p.display()),
            Err(e) => {
                eprintln!("{e}");
                std::process::exit(1)
            }
        },
        "apply" => std::process::exit(actions::apply_main(&cfg, rest)),
        "cancel" => std::process::exit(actions::request_cancel()),
        "-h" | "--help" | "help" => usage(),
        _ => usage(),
    }
}
