# Publication file inventory

Every file intended for tracking was reviewed in the category below. All are UTF-8 text. This allowlisted set excludes original backups, state, logs, credentials, private deployment modules and personal assets.

| File | Review category |
| --- | --- |
| `.gitattributes` | Preserve intentional embedded Go indentation in the existing Ambxst patch |
| `.gitignore` | Repository guardrails / narrowly scoped scanner configuration |
| `.gitleaks.toml` | Repository guardrails / narrowly scoped scanner configuration |
| `LICENSE` | License and attribution notices |
| `NOTICE.md` | License and attribution notices |
| `README.md` | Publication-safe documentation; no raw logs or private identifiers |
| `config/ambxst/binds.json` | Reviewed native preference/keybinding data; writable seed, no account state |
| `config/ambxst/config/bar.json` | Reviewed native preference/keybinding data; writable seed, no account state |
| `config/ambxst/config/compositor.json` | Reviewed native preference/keybinding data; writable seed, no account state |
| `config/ambxst/config/desktop.json` | Reviewed native preference/keybinding data; writable seed, no account state |
| `config/ambxst/config/dock.json` | Reviewed native preference/keybinding data; writable seed, no account state |
| `config/ambxst/config/general.json` | Reviewed native preference/keybinding data; writable seed, no account state |
| `config/ambxst/config/lockscreen.json` | Reviewed native preference/keybinding data; writable seed, no account state |
| `config/ambxst/config/notch.json` | Reviewed native preference/keybinding data; writable seed, no account state |
| `config/ambxst/config/overview.json` | Reviewed native preference/keybinding data; writable seed, no account state |
| `config/ambxst/config/performance.json` | Reviewed native preference/keybinding data; writable seed, no account state |
| `config/ambxst/config/system.json` | Reviewed native preference/keybinding data; writable seed, no account state |
| `config/ambxst/config/theme.json` | Reviewed native preference/keybinding data; writable seed, no account state |
| `config/ambxst/config/workspaces.json` | Reviewed native preference/keybinding data; writable seed, no account state |
| `config/ghostty/config.ghostty` | Native terminal colors/configuration and local CRT shader |
| `config/ghostty/shaders/green-crt.glsl` | Native terminal colors/configuration and local CRT shader |
| `config/gtk-settings.ini` | Native cursor/music/desktop-entry preferences |
| `config/hyprland.lua` | Native compositor/binding configuration; upstream license retained |
| `config/rmpc.desktop` | Native cursor/music/desktop-entry preferences |
| `config/rmpc.ron` | Native cursor/music/desktop-entry preferences |
| `config/theme-seeds/gtk-3.0/gtk.css` | Generated color definitions retained only as writable initial theme |
| `config/theme-seeds/gtk-4.0/gtk.css` | Generated color definitions retained only as writable initial theme |
| `config/theme-seeds/qt5ct/colors/ambxst.colors` | Generated color definitions retained only as writable initial theme |
| `config/theme-seeds/qt6ct/colors/ambxst.colors` | Generated color definitions retained only as writable initial theme |
| `dev/mingw.nix` | Compiler override or locked development-shell expression |
| `dev/shell.nix` | Compiler override or locked development-shell expression |
| `docs/ARCHITECTURE.md` | Publication-safe documentation; no raw logs or private identifiers |
| `docs/FILE-INVENTORY.md` | Publication-safe documentation; no raw logs or private identifiers |
| `docs/INSTALL.md` | Publication-safe documentation; no raw logs or private identifiers |
| `docs/MIGRATION.md` | Publication-safe documentation; no raw logs or private identifiers |
| `docs/PACKAGES.md` | Publication-safe documentation; no raw logs or private identifiers |
| `docs/PRIVACY.md` | Publication-safe documentation; no raw logs or private identifiers |
| `docs/SYSTEM-AUDIT.md` | Publication-safe documentation; no raw logs or private identifiers |
| `docs/TROUBLESHOOTING.md` | Publication-safe documentation; no raw logs or private identifiers |
| `docs/VALIDATION.md` | Publication-safe documentation; no raw logs or private identifiers |
| `flake.lock` | Public upstream revisions and content hashes; no local inputs |
| `flake.nix` | Pinned inputs, public host, private constructor and validation outputs |
| `hosts/workstation/default.nix` | System baseline / explicitly example-only hardware; no actual identifiers |
| `hosts/workstation/hardware-configuration.nix` | System baseline / explicitly example-only hardware; no actual identifiers |
| `licenses/Hyprland-BSD-3-Clause.txt` | License and attribution notices |
| `modules/ambxst.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/android-workstation.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/cursor.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/desktop-integration.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/desktop.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/development.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/flatpak.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/gaming.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/identity.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/login-manager.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/music.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/obsidian-mcp.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/screen-recorder.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/security-tools.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/user-desktop.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/workstation-apps.nix` | Reviewed NixOS package, service or native-file declarations |
| `modules/workstation-hardening.nix` | Reviewed NixOS package, service or native-file declarations |
| `packages/python-tools.nix` | Pinned external-source package recipes; inert import-test placeholder |
| `scripts/check-json.py` | Validation tooling; tests use constructed synthetic data |
| `scripts/privacy-scan.py` | Validation tooling; tests use constructed synthetic data |
| `scripts/test-privacy-scan.py` | Validation tooling; tests use constructed synthetic data |

Total: 66 files. Native Lua/Ghostty/core preferences were compared to the installed sources; transformations are recorded in MIGRATION. Mutable seed content was checked for personal paths, arbitrary commands, account values and private data.
