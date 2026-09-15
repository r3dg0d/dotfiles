# Validation record

Validation date: 2026-09-15. Logs and private machine details stay outside the public repository.

| Check | Result |
| --- | --- |
| `nix flake show` | Pass: workstation host, native-config check, formatter, development shell, constructor library |
| `nix flake check` | Pass: public NixOS evaluation and native Lua/JSON, privacy tests and Gitleaks checks |
| Private deployment evaluation | Pass with the actual generated hardware/account mapping |
| Private full system build | Pass; build only, no activation or boot changes |
| Nix formatting | Formatted and checked using pinned nixfmt 1.5.0 |
| Ghostty native validation | Pass with the preserved config/shader path |
| Packaged shell scripts | ShellCheck: desktop-cache-refresh, clang-cl, gradle9, Obsidian healthcheck/client launcher, yesitsme and TraxOsint |
| Privacy scanner | Working tree and staged content checked; no unresolved findings |
| Gitleaks | No unresolved findings; exact calculator-key false positive documented in `.gitleaks.toml` |
| Actual identifier cross-check | No matches for the source machine ID, product UUID, serial, disk identifiers or hostname in public files |
| File types / size | All publication files are UTF-8 text; no symlinks, binary assets or files over 256 KiB |
| Git review | Every staged file categorized in FILE-INVENTORY; whitespace check and staged diff reviewed |
| Git history / remotes at initial audit handoff | New repository, no commits or remotes; no push during the audit |

## Configuration preservation

Compared evaluated original and private configurations for kernel version/parameters, initrd and kernel modules, NVIDIA package/open-module/modesetting, bootloader/EFI settings, filesystems/swap, firewall, SSH, sudo, user definition and stateVersion: all match. No declared package names were removed. The only additional package name is the generated NixOS user-tmpfiles configuration for writable seeds.

The migration additionally fixes missing explicit ownership on configuration parent directories for a fresh home. Core native tmpfiles links retain their existing replacement behavior; writable seeds preserve existing destinations. This does not constitute an activation test.

## Scope of tests

The flake's native-config check parses Lua with luac and JSON with Python, runs four synthetic-data privacy tests (including staged versus working-tree separation and history scanning), runs the heuristic privacy scan and invokes pinned Gitleaks with default rules plus one exact exception. `nix flake check` evaluates the public host but does not build its entire system closure; the private host was separately built to exercise the real hardware configuration.

Ghostty's own validator checks its configuration; no new terminal window or shader rendering session was launched. ShellCheck treats the private runtime environment file as external using a source annotation, without reading credentials. Nix source pins and hashes are intentionally public and were distinguished from secret values.

Offline formatting initially attempted a large uncached source closure; the successful formatter run used the normal Nix binary cache. No resulting build output or diagnostic log is included in Git.

## Limits and known failures outside this validation scope

The existing live Ambxst border-color IPC error remains. No fresh-install VM, disk restoration, graphical login, visual comparison, recording, suspend/lock timing, credentialed Obsidian API, or application-account test was performed. Flatpak versions, external downloads and private user data are not pinned/reconstructed by these checks. A clean scan is a reviewed heuristic result, not a guarantee about every possible form of sensitive information.

## Initial Git handoff

At the initial audit handoff, the publication set was staged as one coherent initial change. No commits were fabricated and no author identity was invented. Suggested commit after owner review:

```sh
git diff --cached --stat
git diff --cached
python3 scripts/privacy-scan.py --staged
python3 scripts/privacy-scan.py --history
git commit -m "chore: capture audited NixOS workstation configuration"
```

Commit and publication remain owner actions. Configure the desired author identity locally before committing. Keep the private deployment directory out of all public remotes.
