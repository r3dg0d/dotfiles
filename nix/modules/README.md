# Optional NixOS modules

Snapshots of the rice-related `/etc/nixos/r3dg0d-*.nix` modules from the
machine this rice is developed on. They are **not** imported by `nix/rice.nix`;
pull in only what you want, and edit usernames / hardware to match your box.

| Module | What |
|--------|------|
| `fonts.nix` | [Cellforge](https://github.com/r3dg0d/cellforge-font), [Zerodot](https://github.com/r3dg0d/zerodot-font), [NullType](https://github.com/r3dg0d/nulltype-font) from their GitHub repos |
| `quickshell.nix` | Quickshell 0.3.2 (not in nixpkgs; pinned flake tag) |
| `kopuz.nix` | [Kopuz](https://github.com/temidaradev/kopuz) music player (pinned flake + Cachix) |
| `widgets.nix` | Tools the hub / VM Construct widgets expect (playerctl, fwupd, libvirt, …). Change the `users.users.<name>` line. |
| `nvidia.nix` | NVIDIA open kernel module, Wayland modesetting (Turing+) |
| `kernel.nix` | Pins `linuxPackages_7_3` and NVIDIA 595.104.02 — written for an RTX 4090 on nixos-26.05. The galaxy-hub updater can move this pin to a newer series (7.4, 8.0, …) once nixpkgs has it and the NVIDIA module builds. |

Example, from `configuration.nix` (plain NixOS, no flakes or home-manager required):

```nix
imports = [
  /home/<you>/src/dotfiles/nix/rice.nix
  /home/<you>/src/dotfiles/nix/modules/fonts.nix
  /home/<you>/src/dotfiles/nix/modules/quickshell.nix
  /home/<you>/src/dotfiles/nix/modules/kopuz.nix
  /home/<you>/src/dotfiles/nix/modules/widgets.nix
  # /home/<you>/src/dotfiles/nix/modules/nvidia.nix
  # /home/<you>/src/dotfiles/nix/modules/kernel.nix
];
```

These modules assume a channel-based NixOS 26.05 system (`nix-channel`). Kernel
and NVIDIA pins are hardware-specific; do not import `kernel.nix` blindly.
