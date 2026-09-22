# zionsec live workstation architecture

Baseline for agents and megaprompts. Discovered 2026-09-21 on the live host.
Prefer this document over guessing paths. The public sanitized tree is documented in `ARCHITECTURE.md`; this file describes the **live** deploy.

## Machine identity

| Field | Value |
| --- | --- |
| Hostname | `zionsec` |
| User | `neo` |
| NixOS | `26.11.19800101.dirty` (Zokor) |
| Kernel | Linux `7.2.5` (`pkgs.linuxPackages_7_2`) |
| Desktop | Hyprland on Wayland (`XDG_CURRENT_DESKTOP=Hyprland`) |
| Greeter | SDDM (Wayland/Weston kiosk), theme `matrix-code-rain` |
| Shell | bash (`/run/current-system/sw/bin/bash`) |
| GPU | NVIDIA GeForce RTX 4090 |
| Driver | Open kernel module `595.99.02` (`hardware.nvidia.open = true`, `nvidiaPackages.stable`) |
| stateVersion | `26.05` |

## NixOS / flakes architecture

**Live source of truth:** `/etc/nixos` (not a Git repository).

Flake outputs:

- `nixosConfigurations.zionsec` — this machine
- `nixosConfigurations.iosvm-companion` — throwaway Inferno/USB companion VM

Entry modules (from `flake.nix`): `./configuration.nix`, `./modules/workstation-apps.nix`, `./modules/workstation-hardening.nix`, `./modules/android-workstation.nix`, `./modules/obsidian-mcp.nix`.

`configuration.nix` imports hardware plus the rest of `modules/*` (desktop, Ambxst, gaming, Flatpak, AI, security, login manager, etc.).

**Dual rebuild paths (both present):**

1. **Flake (preferred for validation):** `sudo nixos-rebuild … --flake /etc/nixos#zionsec`
2. **Classic wrapper:** `/etc/nixos/rebuild` uses `sources.nix` (pinned nixpkgs tarball) with `nixos-rebuild -I nixpkgs=… -I nixos-config=…` — no flake required for that path.

Flake inputs in live `flake.nix`: pinned nixos unstable tarball URL, `boo`, `durdraw`. Ambxst and nix-flatpak are pulled via `builtins.getFlake` inside modules (not flake inputs).

No Home Manager. No sops/agenix in-tree. No Nix overlays directory observed; customizations use `overrideAttrs`, wrappers, and `packages/*`.

## Canonical repositories

| Path | Role | Git |
| --- | --- | --- |
| `/etc/nixos` | **Live** NixOS config and user desktop sources | **No** |
| `~/dotfiles` | Public sanitized Hyprland/Ambxst NixOS workstation (`github.com/r3dg0d/dotfiles`, branch `main`) | Yes — clean `main…origin/main` |
| `~/dotfiles-private` | Private wrapper template (`nixosConfigurations.zionsec` via `dotfiles.lib.mkWorkstation`, sets `neo` / `zionsec`) | No |
| `~/nixos-workstation` | Older working copy / scratch of the live tree (not authoritative; older than `/etc/nixos`) | No |

Future system edits belong in **`/etc/nixos`**. Sync intentional public-safe pieces into `~/dotfiles` separately. Do not treat `~/nixos-workstation` as the edit root.

## Home Manager

**Not used.** Explicit in `modules/user-desktop.nix`. Desktop files are managed with NixOS `systemd.tmpfiles.rules` linking into `$HOME` from `/etc/nixos/user/…` (via store paths after rebuild).

## Desktop / Wayland stack

| Component | Mechanism | Source of truth |
| --- | --- | --- |
| Hyprland | `programs.hyprland.enable` | NixOS + `/etc/nixos/user/hyprland.lua` → tmpfiles → `~/.config/hypr/hyprland.lua` (store symlink) |
| Ambxst | Pinned flake in `modules/ambxst.nix` (local patches for recorder + axctl) | Package from NixOS; prefs under `~/.config/ambxst/` (writable). `general.json` linked from `/etc/nixos/user/general.json`. **`binds.json` is unmanaged writable** — Ambxst UI edits it; Hyprland binds in `hyprland.lua` are authoritative for actual shortcuts |
| Ghostty | system package + tmpfiles | `/etc/nixos/user/ghostty/` |
| Launcher | fuzzel (`SUPER+SPACE` → `app-launcher`) | `/etc/nixos/user/fuzzel.ini` |
| Lock | `loginctl lock-session` (Ambxst LockscreenService) | Ambxst lockscreen config under `~/.config/ambxst/config/` |
| Portals | gtk + kde + hyprland | `configuration.nix` + `modules/desktop-integration.nix` |
| Screenshots / recording | Ambxst tools + `modules/screen-recorder.nix` | Ambxst + NixOS wrapper |
| File manager | Nautilus | system package |
| Bar / shell UI | Ambxst (not Waybar) | Ambxst |
| Greeter | SDDM Matrix Code Rain | `modules/login-manager.nix`, `packages/sddm/` |

**Do not** re-run Ambxst’s `install hyprland` as a competing bind source; generated compositor config under Ambxst share is not the authoritative Hyprland config.

## Package management strategy

- **Primary:** NixOS modules under `/etc/nixos/modules/*.nix` and `environment.systemPackages` in `configuration.nix`
- **Custom derivations:** `/etc/nixos/packages/` (e.g. helium, lokinet, reclip, eden, apple/Inferno, SDDM theme, python-tools)
- **Flatpak:** declarative `modules/flatpak.nix` (nix-flatpak) + `services.flatpak.enable`
- **Not primary:** Home Manager, Stow
- **Also present:** user `~/.local/bin` (codex, grok-bot, …), `~/.local/opt` (kytyps5, grok-bot), pip/venv AI stacks under `~/ai` (see ai-media / local-ai-tools modules)

## Flatpak

- Remotes: Flathub (system + user)
- Declarative packages: Bazaar, FreeTube, PrismLauncher, Vesktop
- Also installed (not all declarative): Hytale Launcher (user), ProtonPlus, Tor Browser Launcher

## Shell / terminal

- Login shell: bash
- Banner: `zionsec-banner` via `modules/shell-greeting.nix` (`programs.bash.interactiveShellInit`)
- Terminal: Ghostty (config under `/etc/nixos/user/ghostty/`)
- No Starship observed in NixOS modules
- Ambxst can launch tmux (`ambxst run tmux`)

## NVIDIA / graphics

- `services.xserver.videoDrivers = [ "nvidia" ]` (driver entry only; X server not enabled for the session)
- `hardware.nvidia.modesetting.enable = true`, `open = true`, `nvidiaSettings = true`
- Vulkan present (instance 1.4.x)
- CUDA: Ollama (`ollama-cuda`), nvidia-container-toolkit for Docker GPU, ComfyUI / LLaDA tooling in AI modules
- Known recorder issue: NVENC API mismatch handled in `modules/screen-recorder.nix` + Ambxst backend patch

## Gaming stack

- Steam, GameMode, Gamescope (`modules/gaming.nix`)
- Flatpak: PrismLauncher, ProtonPlus, Hytale launcher
- Eden emulator module (`modules/eden.nix`)

## AI / development tooling

- Ollama CUDA on localhost:11434
- ComfyUI / AllTalk / LLaDA / aiwmremover modules
- Dev: Rust (rustc/cargo), Python+pipx, Clang/GCC, CMake/Ninja, Zig, gh, Codex CLI, Claude Code
- Docker enabled (neo in `docker` group)
- Obsidian MCP module (`modules/obsidian-mcp.nix`)

## Privacy / networking

- NetworkManager
- Firewall enabled (`workstation-hardening.nix`), SSH **disabled**
- Mullvad VPN (daemon + GUI; no account in config)
- Lokinet + Firefox/Helium loki-related modules
- Tor Browser via Flatpak

## System services (notable)

Enabled/active observed: NetworkManager, bluetooth, docker, mullvad-daemon, ollama.

Failed user unit (stale when Obsidian API down): `obsidian-rest-api-healthcheck.service` (curl to `127.0.0.1:27124` unreachable). Not a system boot failure.

PipeWire: enabled in config; user session units may show masked at system level (normal for user bus audio).

## Storage

- Root: ext4 on `nvme0n1p2`, ~1.8T, ~754G used / ~986G free (~44%)
- Nix store on same filesystem
- Large caches (baseline only): `~/.cache` ~88G, Steam `~/.local/share/Steam` ~192G, Flatpak ~5.4G
- `nix.optimise.automatic = true`; no `nix.gc.automatic` found in hardening module
- System profile generations accumulated through `system-87` (many generations; cleanup is a future task, not this bootstrap)

## Git / GitHub workflow

- Live `/etc/nixos`: **not** a git repo — edits are local until manually synced
- Public publish path: `~/dotfiles` → `https://github.com/r3dg0d/dotfiles.git` (`main`)
- `gh` authenticated as `r3dg0d` (HTTPS) — usable
- Do not force-push; do not commit secrets

## Documentation location

| Location | Contents |
| --- | --- |
| `/etc/nixos/README.md`, `REPORT.md`, `validation.md` | Live machine notes |
| `~/dotfiles/docs/` | Public docs (`ARCHITECTURE.md`, `SYSTEM-AUDIT.md`, `VALIDATION.md`, …) |
| **This file** `~/dotfiles/docs/ZIONSEC.md` | Live zionsec agent baseline |

Ideal follow-up: copy or symlink this file into `/etc/nixos/` once writable with sudo.

## Validation commands

```bash
# As root (needed for live /etc/nixos: some backup-* dirs are mode 0700)
cd /etc/nixos
sudo nix flake check --no-build
sudo nixos-rebuild dry-build --flake .#zionsec

# Classic non-flake path
sudo /etc/nixos/rebuild dry-build
```

Bootstrap note (2026-09-21): as `neo`, live `nix flake check` fails with permission denied on `backup-comprehensive-*`. A readable rsync copy under `~/.cache/zionsec-flake-audit` (excluding those dirs) passed `nix flake check --no-build` and `nixos-rebuild dry-build --flake .#zionsec` (exit 0). Re-run with sudo on the live tree before trusting activation.

## Safe rollback

```bash
# List generations
ls -1 /nix/var/nix/profiles/system-*-link

# Roll back one generation (or pick N)
sudo nix-env --rollback -p /nix/var/nix/profiles/system
# or: sudo nixos-rebuild switch --rollback
# Greeter / tty1 conflicts: prefer `rebuild boot` + reboot for display-manager changes
```

## Important warnings / existing problems

1. **`/etc/nixos` is not in Git** — risk of untracked drift vs `~/dotfiles`.
2. **Many system generations** (~87) — consider planned GC later.
3. **Mode-0700 backup dirs** under `/etc/nixos` block unprivileged flake evaluation.
4. **Ambxst border-color IPC / quoting** issue documented in public troubleshooting (pre-existing).
5. **`ambxst reload` axctl race** — mitigated by local patch in `modules/ambxst.nix`; revisit on Ambxst upgrades.
6. **Obsidian REST healthcheck** fails when Obsidian Local REST API is not listening — expected if Obsidian is closed.
7. **Display manager changes** conflict with `autovt@tty1` — use `boot` + reboot, not live `switch` from tty1.
8. **Executor/subagent machineId routing** may fail in Grok Bot; parent Shell with `machineId` for zionsec works.

## Where future changes belong

| Change | Edit here |
| --- | --- |
| NixOS system packages / services | `/etc/nixos/modules/*.nix` or `configuration.nix` |
| Flake inputs / outputs | `/etc/nixos/flake.nix`, `flake.lock` |
| Hyprland keybinds / compositor Lua | `/etc/nixos/user/hyprland.lua` then rebuild |
| Ambxst `general.json` seed | `/etc/nixos/user/general.json` then rebuild |
| Ambxst UI prefs / many JSON | `~/.config/ambxst/config/*.json` (writable; not all declarative) |
| Ambxst binds panel data | `~/.config/ambxst/binds.json` (writable) — keep in sync with Hyprland Lua |
| Ghostty | `/etc/nixos/user/ghostty/` then rebuild |
| Fuzzel | `/etc/nixos/user/fuzzel.ini` then rebuild |
| Flatpak app list | `/etc/nixos/modules/flatpak.nix` |
| Gaming | `/etc/nixos/modules/gaming.nix` |
| NVIDIA / kernel | `/etc/nixos/configuration.nix` |
| Custom packages | `/etc/nixos/packages/` |
| User scripts / local bins | prefer a NixOS module or `/etc/nixos/user/` + tmpfiles; avoid undocumented `$HOME` sprawl |
| Systemd user units (declarative) | NixOS modules (`systemd.user.*`) |
| Secrets | not in-tree; keep out of Git; Mullvad/accounts via their GUIs |
| Public documentation | `~/dotfiles/docs/` |
| Live-only documentation | this file + `/etc/nixos/README.md` |

## Do not edit generated / linked files directly

- `~/.config/hypr/hyprland.lua` (store symlink via tmpfiles)
- `~/.config/ghostty/config.ghostty` and shader symlink
- `~/.config/ambxst/config/general.json` (store symlink)
- `~/.config/fuzzel/fuzzel.ini` (store symlink)
- Ambxst-generated compositor configs under Ambxst share (do not adopt as source of truth)
- `/nix/store/*` anything
- Hardware UUIDs / private identity in `hardware-configuration.nix` — do not publish

Edit the sources under `/etc/nixos/user/` (or the relevant module), then rebuild, so tmpfiles refresh the links.
