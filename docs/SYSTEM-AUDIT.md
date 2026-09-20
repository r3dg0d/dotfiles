# System audit

Read-only discovery: 2026-09-15. Publication-safe summary; private identifiers and raw command output are deliberately absent.

## System, kernel, boot and GPU

- NixOS 26.11 development build, Nix 2.34.8, x86_64, running Linux 7.2.5. `system.stateVersion` remains 26.05; it is a compatibility setting, not the current release.
- EFI systemd-boot, EFI variable writes enabled, boot editor disabled. No GRUB, lanzaboote or declared Secure Boot integration found. Firmware Secure Boot state was not independently measured.
- Intel virtualization/microcode support, ext4 root, vfat boot with restrictive masks, no declared swap. Generated disk identifiers remain private. Initrd modules: xhci_pci, ahci, nvme, usbhid, usb_storage, sd_mod; kernel module kvm-intel.
- NVIDIA RTX 4090, runtime driver 595.99.02, `hardware.nvidia.open = true`, modesetting, stable driver from the selected kernel package, graphics/32-bit support. Open refers to the kernel module; the stack still requires unfree components. CUDA comes through Ollama, not a newly introduced global CUDA override. No added NVIDIA environment-variable bundle or GPU/kernel changes.

## Desktop and display stack

- Live Hyprland 0.56.2 with native Lua; active monitor 3440×1440 at roughly 60 Hz, scale 1. Configuration deliberately uses preferred/auto rather than an EDID, serial or fixed connector.
- Ambxst supplies shell, launcher, notifications/toolbox, overview, clipboard, lock/idle actions and wallpaper UI; no independent Waybar or replacement notification daemon was introduced. XWayland is enabled. GTK and Hyprland portals are configured; PipeWire supplies desktop audio.
- Single Ambxst startup callback. Scrolling layout; column width 0.5, follow focus, final fullscreen-on-one-column true. Lua includes animations, shadow, blur, US keyboard, three-finger workspace gesture and existing window/XWayland rules.
- Super+Return terminal, Super+Space launcher, Super+V clipboard, Super+Alt+V floating, Print screenshot, Ctrl+Print recorder; numbered workspaces 1–10 and scrolling focus/swap/resize controls preserved.
- Ambxst preferences select Terminus for UI/monospace text and include top bar, left floating dock, 2×5 overview, green theme, lock at 300 s, screen off at 330 s, suspend at 1800 s. These are configured intentions, not independently timing-tested behavior.
- Existing runtime error: Ambxst applies double-quoted `rgb(...)` border colors that Hyprland rejects. This existed before migration. Stored Lua syntax can be valid while runtime IPC fails.
- Generated theme output under GTK/Qt is captured only as a writable initial palette. Wallpaper assets, presets state, clipboard databases and keys are excluded.

## Shell and terminal

Bash 5.3p15; the only discovered personal Bash edit adds the local bin directory to PATH. This is expressed with `environment.localBinInPath`. Ghostty uses JetBrains Mono, size 10, black/green palette, block cursor and a configurable GLSL CRT shader. rmpc uses the existing compact native RON. No existing Zsh/Fish/Starship/zellij customization was found in the inspected home root/config directory. Git's credential helper referenced a concrete Nix store binary; that account-specific file is excluded and GitHub authentication should recreate it locally.

## Nix architecture and drift

`/etc/nixos` and a home workspace both contain flakes, a legacy evaluator, modules and backups; neither was a Git repository. The only current source difference found in corresponding active files was package-list formatting in `workstation-apps.nix`, not a package change. Managed live Hyprland/Ghostty/rmpc/GTK files matched the active sources. The executing tool account was root; workstation account discovery was done separately.

No Home Manager integration or user-profile packages were found. Existing user files are already partially declarative through NixOS tmpfiles. Custom modules cover development, desktop, gaming, music, security tools, Android, recording, Flatpak and Obsidian MCP. Local package overrides cover MinGW and pinned Python projects; no overlay framework.

Stale comments described the system as non-flake, called Linux 7.2 LTS, or described an obsolete recorder wrapper approach. The live build differs in derivation identity from older workspace result links; those links are build history, not authoritative configuration. Backups and old audit logs were not migrated.

## Services and scripts

At discovery both `systemctl --failed` and its user equivalent listed zero failed units. Ly's display-manager service was active. (The greeter has since been replaced by SDDM with the Matrix Code Rain theme; this paragraph records the state at discovery.) System services include NetworkManager, Bluetooth, Flatpak management, Mullvad, Ollama, Nix and existing journaling/hardening. User units include MPD, desktop-cache-refresh service/path, Obsidian and its REST API healthcheck timer, PipeWire/WirePlumber and standard user units. No manually authored user unit directory was found. A later process-name-only inventory confirmed Firefox, Ghostty, Ambxst/Quickshell, axctl, XWayland, MPD/rmpc, ttyper, Vesktop and wl-paste running. Some speech-dispatcher/helper processes were defunct; this was recorded without killing or restarting their parents.

Packaged workflow scripts include desktop/icon cache refresh, recorder fallback, Obsidian healthcheck/client launch, clang-cl/gradle9, and yesitsme/TraxOsint. Existing source pins, runtime dependencies and wrappers are retained. The original install/rebuild scripts were not copied because they target the source machine and backup layout.

## Application classification

| Class | Discovered examples and decision |
| --- | --- |
| A — useful configuration | hypr, ghostty, ambxst preference JSON/binds, rmpc, GTK cursor settings, theme seed files |
| B — generated/state | dconf database, GTK/Qt generated colors (seed only), Ambxst generated compositor files, caches, pulse/WirePlumber state, desktop launcher caches |
| C — machine-specific | generated hardware, monitor/device identity, generated Thunderbird desktop IDs and mime associations, private deployment identity |
| D — private/sensitive | browser/mail profiles, gh, Obsidian/MCP environment and vaults, AI client state, Mullvad accounts, Vesktop sessions, Wireshark captures/settings requiring review, GPG/SSH/cert/key stores |
| E — unreviewed optional state | EasyEffects presets, QtProject settings, qBittorrent settings, Nautilus metadata, Matcha and other app state; omitted pending intentional selection |

No broad `.config` or `.local` copy. Personal content in Documents, Downloads, music libraries, pictures and recordings was not inspected for publication. No shell history or credential store was imported.

## Declarative versus imperative

Already declarative: system/packages, custom services and wrappers, Flatpak app list, core desktop native files. Improved: locked external flake graph, reusable identity, local bin PATH, initial Ambxst/bind/theme preferences. Reasonably imperative: app logins, models, games, music, wallpaper selection, Obsidian vault/plugin setup and mutable UI preferences. Generated: databases, caches, icons, runtime compositor outputs. Unknown: application settings outside the explicit allowlist.

## Cleanup candidates and limitations

The duplicate scrolling flag was consolidated to its existing final true value. Dormant dwindle/master settings, example mouse device and layout-only shortcuts remain to avoid workflow guesses. The Ambxst restart patch uses broad force-termination and should be revisited upstream. MPD/local API bindings are loopback. Account authentication and firewall policy were not changed.

No activation, reboot, rendering comparison, recording test, credentialed API test or restore-from-blank-disk test was performed. Flatpaks and private data are not reproducibly pinned. See VALIDATION for precise evaluated/build results rather than assuming full reproducibility.
