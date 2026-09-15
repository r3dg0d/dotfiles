# Architecture

```text
flake.nix (locked nixpkgs, boo, durdraw, Ambxst, nix-flatpak)
└── lib.mkWorkstation { modules = [ private hardware and identity ]; }
    ├── hosts/workstation/default.nix
    │   ├── kernel / EFI boot / NVIDIA / networking / account / PipeWire
    │   ├── identity: parameterized login and home; local bin on PATH
    │   ├── desktop / Ambxst / cursor / user-desktop / login-manager
    │   ├── development / security-tools / gaming / music
    │   └── Flatpak / desktop-integration / screen-recorder
    ├── workstation-apps → packages/python-tools.nix, boo, durdraw
    ├── workstation-hardening
    ├── android-workstation
    └── obsidian-mcp
```

The public `nixosConfigurations.workstation` adds example hardware to the same constructor. A private wrapper adds actual generated hardware instead. No Home Manager, overlays, flake framework, or standalone user profile is required. Package customizations use local `overrideAttrs`, wrappers and `callPackage`. `dev/shell.nix` uses the same pinned pkgs through `nix develop`.

`allowUnfree` and Android SDK license acceptance are retained. Ambxst's own nixpkgs stays independently pinned. All external project source is fetched; application source trees and compiled binaries are not vendored.

## Native file ownership

- NixOS `systemd.tmpfiles.rules` links the selected user's Hyprland Lua, Ghostty config/shader, GTK cursor settings, rmpc config and desktop entries to store files.
- User tmpfiles copies each Ambxst preference/binding JSON and generated GTK/Qt color seed once. These must remain writable for Ambxst's UI. No clipboard, authentication, cache or application state is deployed.
- Ambxst starts once through the existing `hyprland.start` callback. Its generated compositor configurations under local share are not imported; re-running its installer would create a competing source of bindings.
- Ambxst can still apply compositor settings at runtime, which explains differences between Lua defaults and the visible session. Its active border synchronization currently has a quoting error; see troubleshooting.

## Service ownership

System: NetworkManager, PipeWire integration, Bluetooth, Flatpak installer, Mullvad, Ollama (CUDA, loopback), Ly and existing security policy. User: MPD, desktop/icon cache refresh path/service, Obsidian graphical session service and API healthcheck timer. These services existed before migration. No new network service was introduced.

Existing generic user services and user tmpfiles are NixOS-wide; the linked core configs and MPD are scoped to the selected account, while writable seeds can apply to other user managers. Review that if turning this personal setup into a multi-user host.

The recorder wrapper handles direct calls; Ambxst needs a separate backend patch because its launcher prepends bundled tools. Its existing axctl restart patch is retained and remains a maintenance risk when upgrading.
