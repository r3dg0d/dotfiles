# Troubleshooting

## Boot, login and NVIDIA

Keep a known-good boot generation. Ly's display-manager conflicts with the tty1 getty; activating it from that TTY can end the current login. Prefer `nixos-rebuild boot` and a deliberate reboot for that transition. The source setup uses systemd-boot, EFI writes and Linux 7.2; do not interpret the old LTS comment as a kernel-support promise.

Preserve the current stable NVIDIA package/open-module/modesetting combination when first reproducing the machine. Do not add generic NVIDIA environment-variable recipes. The hardware baseline is an RTX 4090 with 32-bit graphics and audio for Steam. Different GPUs require a separately reviewed module change.

## Ambxst colors and binding ownership

`hyprctl configerrors` in the original session reported invalid double-quoted `rgb(...)` border colors produced by Ambxst runtime synchronization. This is distinct from a Lua syntax error. It remains an upstream/runtime issue in the retained setup; disabling border-color synchronization or patching axctl may help, but neither was applied during migration. A successful flake check does not certify a clean running compositor.

The Lua file is authoritative for actual global shortcuts. Ambxst's Settings keybind panel edits its separate JSON. Keep both in sync manually; do not import generated local-share Hyprland files on top of the retained configuration. OCR/mirror tools had no usable external entry point in the retained setup, so their proposed shortcuts remain unbound. Dwindle-only toggles remain dormant under scrolling.

Ambxst can override visual values at runtime. The public snapshot therefore includes both the Lua baseline and its mutable preferences. Copy-once seeds intentionally do not reset existing UI choices when rebuilding. Core native files linked through tmpfiles are read-only store links: edit repository sources.

## Recording and shell reload

The original configuration documents an NVENC API mismatch: driver 595.99.02 exposes 13.0 while GPU Screen Recorder's headers require 13.1. Existing wrappers request CPU fallback; Ambxst also needs a backend argument patch because it prepends bundled binaries. This was preserved, not newly reproduced with a recording test.

An existing Ambxst backend patch force-terminates matching axctl daemons and clears the stale socket before restart. It addresses the source setup's reload race but can affect other matching processes. Keep it under review on version updates; no daemon was restarted in this audit.

Phosphor fonts are registered at system level to address the existing missing-icon issue. Bundled tools use lower package priority, with only the patched Ambxst launcher winning its own collision.

## Services and applications

Inspect without changing state:

```sh
systemctl --failed
systemctl --user --failed
systemctl --user status mpd obsidian
journalctl --user -u obsidian-rest-api-healthcheck --since today
```

MPD uses the user's PipeWire/Pulse session and music directory. On a fresh machine Obsidian's healthcheck will fail until the app, Local REST API plugin, private environment and trusted certificate are set up; the service does not provision them. Its graphical-session target must actually be reached by the login session.

Flatpak app installation needs networking and may continue after a rebuild. Accounts and runtimes are external state. Steam icon refresh uses local artwork and a fallback; it does not fetch personal content from the network. Existing Firefox/mail defaults may need selecting again because generated desktop IDs were not migrated.

## Evaluation and upgrades

Run `nix flake check` and a build before activation. `nix fmt` uses the formatter locked with nixpkgs. Revision-pinned URLs require deliberate edits before `nix flake update` changes versions. Refresh the private wrapper's `dotfiles` input after source changes. Never fix an evaluation problem by pointing public files at a private home directory or secret file.
