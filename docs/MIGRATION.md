# Migration record

## Preserved

The installed `/etc/nixos` tree was the base, compared against the home workspace and live managed files. Existing functional module boundaries, kernel/boot/NVIDIA choices, firewall/sudo/SSH policy, packages, Flatpak list, custom package patches, services and desktop workflow were retained. Native Lua, Ghostty CRT colors/shader, rmpc and cursor settings remain directly editable source files.

## Moved

The system entry moved to `hosts/workstation/default.nix`; native `user/` content became `config/`. Custom package and development expressions retain `packages/` and `dev/`. Originals were neither moved nor changed: these operations apply only to the new copy. No old Git history existed to preserve.

## Converted to Nix

- Ambxst and nix-flatpak are explicit locked flake inputs at their existing revisions, replacing nested `builtins.getFlake` expressions.
- Account and home references use `workstation.username` / `workstation.homeDirectory`; native capture commands use quoted `$HOME` paths.
- Explicitly create user-owned parent directories for native config links, avoiding root-owned implicit parents on a fresh home.
- Bash's installer PATH edit is represented by NixOS `environment.localBinInPath`.
- Ambxst preference/binding JSON and GTK/Qt color output become writable, copy-once seeds. Existing destinations are deliberately preserved on activation.
- The development shell uses the flake's pkgs rather than a second fetch expression.

## Converted to Home Manager

None. Existing NixOS ownership is sufficient, and a Home Manager adoption would add migration/conflict risk without solving an immediate missing capability.

## Cleaned up in the copy

Removed the duplicate scrolling flag while preserving its final true value. Corrected obsolete non-flake/LTS/recorder commentary. Removed host-specific legacy evaluator/rebuild/install entry points from the publication set. Replaced an unverified build-time API-key value with an explicit inert placeholder. No usable credentials are needed for Python import checks.

## Excluded from Git

Backups, logs, build outputs, test captures, browser/mail/AI profiles, tokens, shell history, private keys/certificates, Obsidian vaults and plugins, clipboard databases/key, application authentication, game/model/music data, wallpapers and personal assets. The custom rmpc SVG was omitted because redistribution provenance was not established; its launcher uses a generic terminal icon. The CRT shader is retained as workstation configuration, with provenance noted in NOTICE.

Generated MIME mappings referenced unstable per-install Thunderbird desktop IDs; they were excluded rather than propagated as reusable defaults. The store-path GitHub credential helper is recreated privately by authentication tooling. Generated Ambxst alternate compositor configurations are not imported or copied.

## Machine-specific

Public host/account names are neutral. Public hardware is visibly labeled as an example with symbolic disk labels. The actual generated hardware module and existing account/hostname mapping are in a separate private deployment wrapper, outside Git. No disk label, partition, filesystem, bootloader or active system setting was changed.

## Requires manual configuration

Authentication on fresh installs; networking/VPN/app accounts; Obsidian vault, plugin, credentials and certificate trust; models, game libraries, music, wallpaper selection; copying desired writable seed updates into an existing account. Back up native destination files before first activation on a different installation because core `L+` rules replace them.

## Future improvements

Fix Ambxst border-color IPC quoting and revisit its axctl shutdown race upstream. Review redundant/dormant keybindings with the user. Consider Home Manager only if user configuration grows enough to justify a deliberate ownership migration. Add privacy-reviewed screenshots and a tested restore procedure. Lock Flatpak commits separately if exact application-version reconstruction becomes a requirement.
