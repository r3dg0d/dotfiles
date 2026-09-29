//! Small shared helpers for the NixOS Updater and Storage Optimizer backends:
//! XDG paths, config loading, atomic JSON state, command execution with
//! timeouts, JSON-lines events for the QML frontends, and notifications.

use serde::Serialize;
use std::fs;
use std::io::{self, Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"))
}

fn xdg(var: &str, fallback: &str) -> PathBuf {
    match std::env::var_os(var) {
        Some(v) if Path::new(&v).is_absolute() => PathBuf::from(v),
        _ => home().join(fallback),
    }
}

pub fn config_dir(app: &str) -> PathBuf {
    xdg("XDG_CONFIG_HOME", ".config").join(app)
}
pub fn cache_dir(app: &str) -> PathBuf {
    xdg("XDG_CACHE_HOME", ".cache").join(app)
}
pub fn state_dir(app: &str) -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state").join(app)
}
pub fn data_home() -> PathBuf {
    xdg("XDG_DATA_HOME", ".local/share")
}

/// Load `<config_dir>/config.toml` into `T`, falling back to `T::default()`
/// for a missing file. A malformed file is reported, never silently ignored.
pub fn load_config<T>(app: &str) -> (T, Option<String>)
where
    T: serde::de::DeserializeOwned + Default,
{
    let path = config_dir(app).join("config.toml");
    match fs::read_to_string(&path) {
        Ok(text) => match toml::from_str::<T>(&text) {
            Ok(cfg) => (cfg, None),
            Err(e) => (T::default(), Some(format!("{}: {}", path.display(), e))),
        },
        Err(e) if e.kind() == io::ErrorKind::NotFound => (T::default(), None),
        Err(e) => (T::default(), Some(format!("{}: {}", path.display(), e))),
    }
}

/// Write a commented default config if none exists yet. Never overwrites.
pub fn ensure_default_config(app: &str, contents: &str) -> io::Result<PathBuf> {
    let dir = config_dir(app);
    let path = dir.join("config.toml");
    if !path.exists() {
        fs::create_dir_all(&dir)?;
        write_atomic(&path, contents.as_bytes(), 0o644)?;
    }
    Ok(path)
}

/// Write via a temp file + rename so readers (the QML FileViews) never see a
/// half-written document.
pub fn write_atomic(path: &Path, data: &[u8], mode: u32) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let tmp = path.with_extension(format!("tmp.{}", std::process::id()));
    {
        let mut f = fs::File::create(&tmp)?;
        f.set_permissions(fs::Permissions::from_mode(mode))?;
        f.write_all(data)?;
        f.sync_all()?;
    }
    fs::rename(&tmp, path)
}

pub fn write_json<T: Serialize>(path: &Path, value: &T, mode: u32) -> io::Result<()> {
    let mut data = serde_json::to_vec_pretty(value).map_err(io::Error::other)?;
    data.push(b'\n');
    write_atomic(path, &data, mode)
}

pub fn read_json(path: &Path) -> Option<serde_json::Value> {
    serde_json::from_slice(&fs::read(path).ok()?).ok()
}

pub fn now_unix() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

pub fn mtime_unix(meta: &fs::Metadata) -> i64 {
    meta.modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Emit one JSON object per line on stdout; the QML side reads these with a
/// SplitParser. Flushes immediately so progress is live.
pub fn emit<T: Serialize>(event: &T) {
    let mut out = io::stdout().lock();
    if serde_json::to_writer(&mut out, event).is_ok() {
        let _ = out.write_all(b"\n");
        let _ = out.flush();
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct CmdOutput {
    pub ok: bool,
    pub code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
    pub timed_out: bool,
}

/// Run a command to completion with a hard timeout. Stdin is closed so a
/// command can never block waiting for interactive input.
pub fn run(program: &str, args: &[&str], timeout: Duration) -> CmdOutput {
    run_with_stdin(program, args, None, timeout)
}

pub fn run_with_stdin(program: &str, args: &[&str], stdin: Option<&str>, timeout: Duration) -> CmdOutput {
    let mut cmd = Command::new(program);
    cmd.args(args)
        .stdin(if stdin.is_some() { Stdio::piped() } else { Stdio::null() })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .env("LC_ALL", "C.UTF-8")
        .env("GIT_TERMINAL_PROMPT", "0");
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            return CmdOutput { ok: false, code: None, stdout: String::new(), stderr: format!("{program}: {e}"), timed_out: false }
        }
    };
    if let Some(mut pipe) = child.stdin.take() {
        if let Some(input) = stdin {
            let _ = pipe.write_all(input.as_bytes());
        }
        // Dropping the pipe closes stdin.
    }
    // Drain pipes on threads so a chatty command cannot deadlock on a full pipe.
    let mut so = child.stdout.take().unwrap();
    let mut se = child.stderr.take().unwrap();
    let t_out = std::thread::spawn(move || {
        let mut s = String::new();
        let _ = so.read_to_string(&mut s);
        s
    });
    let t_err = std::thread::spawn(move || {
        let mut s = String::new();
        let _ = se.read_to_string(&mut s);
        s
    });
    let start = Instant::now();
    let mut timed_out = false;
    let status = loop {
        match child.try_wait() {
            Ok(Some(st)) => break Some(st),
            Ok(None) if start.elapsed() > timeout || cancelled() => {
                timed_out = start.elapsed() > timeout;
                let _ = child.kill();
                break child.wait().ok();
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(25)),
            Err(_) => break None,
        }
    };
    let stdout = t_out.join().unwrap_or_default();
    let stderr = t_err.join().unwrap_or_default();
    let code = status.and_then(|s| s.code());
    CmdOutput { ok: !timed_out && code == Some(0), code, stdout, stderr, timed_out }
}

pub fn have(program: &str) -> bool {
    if program.contains('/') {
        return Path::new(program).exists();
    }
    std::env::var_os("PATH")
        .map(|p| std::env::split_paths(&p).any(|d| d.join(program).is_file()))
        .unwrap_or(false)
}

/// Desktop notification through the session's notification server (Ambxst's).
pub fn notify(app_name: &str, icon: &str, summary: &str, body: &str) {
    if !have("notify-send") {
        return;
    }
    let _ = run(
        "notify-send",
        &["--app-name", app_name, "--icon", icon, summary, body],
        Duration::from_secs(5),
    );
}

pub fn human_bytes(b: u64) -> String {
    const UNITS: [&str; 6] = ["B", "KB", "MB", "GB", "TB", "PB"];
    let mut v = b as f64;
    let mut i = 0;
    while v >= 1000.0 && i < UNITS.len() - 1 {
        v /= 1000.0;
        i += 1;
    }
    if i == 0 {
        format!("{b} B")
    } else if v >= 100.0 {
        format!("{v:.0} {}", UNITS[i])
    } else {
        format!("{v:.1} {}", UNITS[i])
    }
}

/// Cooperative cancellation: SIGTERM/SIGINT set a flag that long-running
/// loops poll, so cancelling from the UI stops cleanly without partial state.
static CANCELLED: AtomicBool = AtomicBool::new(false);

extern "C" fn on_signal(_: libc::c_int) {
    CANCELLED.store(true, Ordering::SeqCst);
}

pub fn install_cancel_handler() {
    unsafe {
        libc::signal(libc::SIGTERM, on_signal as extern "C" fn(libc::c_int) as libc::sighandler_t);
        libc::signal(libc::SIGINT, on_signal as extern "C" fn(libc::c_int) as libc::sighandler_t);
    }
}

pub fn cancelled() -> bool {
    CANCELLED.load(Ordering::SeqCst)
}

/// Single-instance lock (flock) so a timer check and a UI refresh, or two
/// scans, never run concurrently. Returns None if another holder exists.
pub struct Lock(#[allow(dead_code)] fs::File);

pub fn try_lock(path: &Path) -> Option<Lock> {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let f = fs::OpenOptions::new().create(true).write(true).truncate(false).open(path).ok()?;
    use std::os::fd::AsRawFd;
    let r = unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if r == 0 {
        Some(Lock(f))
    } else {
        None
    }
}

/// (size, used, available) in bytes, with "used" as df reports it.
pub fn statvfs(path: &Path) -> Option<(u64, u64, u64)> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    let c = CString::new(path.as_os_str().as_bytes()).ok()?;
    let mut s: libc::statvfs = unsafe { std::mem::zeroed() };
    if unsafe { libc::statvfs(c.as_ptr(), &mut s) } != 0 {
        return None;
    }
    let frsize = s.f_frsize as u64;
    let size = s.f_blocks as u64 * frsize;
    let avail = s.f_bavail as u64 * frsize;
    let free = s.f_bfree as u64 * frsize;
    Some((size, size.saturating_sub(free), avail))
}

pub fn uid() -> u32 {
    unsafe { libc::getuid() }
}

/// Why a `pkexec` call ended before the privileged program ran, from its
/// output. None when the output doesn't look like an authentication failure.
pub fn pkexec_failure(output: &[String]) -> Option<&'static str> {
    let has = |needle: &str| output.iter().any(|l| l.contains(needle));
    if has("No authentication agent") {
        Some("No polkit authentication agent is running (it is provided by the zionsec-tools-widgets service).")
    } else if has("dismissed") {
        Some("Authentication was cancelled.")
    } else if has("Not authorized") || has("Error executing command as another user") {
        Some("Authentication failed or was not authorized.")
    } else {
        None
    }
}

/// PATH for helper child processes. TOOLS_PATH is baked in at build time
/// (curl, git, coreutils, libnotify from the Nix closure); system tools come
/// from the running system. Shared by both backends to avoid duplicated logic.
pub fn setup_tools_path(privileged: bool) {
    let tools = option_env!("TOOLS_PATH").unwrap_or("");
    let system = "/run/wrappers/bin:/run/current-system/sw/bin";
    let path = if privileged {
        format!("{tools}:{system}")
    } else {
        let user = std::env::var("PATH").unwrap_or_default();
        format!("{tools}:{system}:{user}")
    };
    std::env::set_var("PATH", path);
}

/// Current system profile generation number, if resolvable.
pub fn current_system_generation() -> Option<u64> {
    let link = std::fs::read_link("/nix/var/nix/profiles/system").ok()?;
    let name = link.to_string_lossy();
    name.strip_prefix("system-")?
        .strip_suffix("-link")?
        .parse()
        .ok()
}

/// Human-readable duration from milliseconds (e.g. "1m 12s", "45s", "3.2s").
pub fn format_duration_ms(ms: u64) -> String {
    if ms < 1000 {
        return format!("{ms}ms");
    }
    let secs = ms / 1000;
    if secs < 60 {
        let rem = ms % 1000;
        if rem == 0 {
            format!("{secs}s")
        } else {
            format!("{}.{}s", secs, rem / 100)
        }
    } else {
        let m = secs / 60;
        let s = secs % 60;
        if m >= 60 {
            let h = m / 60;
            let mm = m % 60;
            format!("{h}h {mm}m {s}s")
        } else {
            format!("{m}m {s}s")
        }
    }
}

