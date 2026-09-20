# Installation and rebuilds

## Preconditions

This is an x86_64-linux workstation with Intel CPU support and an NVIDIA RTX 4090 baseline. Inspect `hosts/workstation/default.nix` before using different hardware. It enables systemd-boot/EFI writes, Linux 7.2, NVIDIA open modules and the stable driver, 32-bit graphics/audio, unfree packages and Android SDK license acceptance. No partitioning or disk formatting is automated.

Install NixOS normally, enable `nix-command` and `flakes`, and obtain the public repository:

```sh
git clone https://github.com/r3dg0d/dotfiles.git dotfiles
cd dotfiles
nix flake show
nix flake check
```

The public host's root/boot labels are examples. Do not rename or format disks to satisfy them. Keep the actual generated `hardware-configuration.nix` in a **separate private directory**, never in this repository. It contains disk identifiers and may include other machine details. Disk encryption keys and credentials must never be imported into a flake.

## Private deployment (recommended)

Create a private directory outside the clone, e.g. `../dotfiles-private`, with mode 0700. Copy your installation's generated hardware module there. Create `flake.nix`:

```nix
{
  inputs.dotfiles.url = "path:/absolute/path/to/dotfiles";
  outputs = { dotfiles, ... }: {
    nixosConfigurations.workstation = dotfiles.lib.mkWorkstation {
      modules = [
        ./hardware-configuration.nix
        {
          workstation.username = "user"; # replace with your existing login
          networking.hostName = "workstation"; # choose your actual hostname
        }
      ];
    };
  };
}
```

Use your actual clone path and account. A local path is convenient during migration; after publication a Git input pinned in the private lock makes the deployment portable. This constructor deliberately does not import the public example hardware. An optional `workstation.homeDirectory` supports a nonstandard home path without whitespace.

From the private directory:

```sh
nix flake lock
nix flake check
nix build .#nixosConfigurations.workstation.config.system.build.toplevel
sudo nixos-rebuild boot --flake .#workstation
```

Review the build before running the last command, then reboot deliberately. On the original workstation a private wrapper was prepared separately with its existing host output; use that wrapper's README for the exact command. No activation was performed during migration.

After changing the public clone, refresh the private input before validating/rebuilding:

```sh
nix flake update dotfiles
nix flake check
```

Keep the private lock and hardware out of public Git. Nix copies referenced source modules to its store: private identifiers may appear locally there, but **secrets must not**.

## Account and application setup

The configuration creates the selected user but contains no password/hash. On a fresh installation, set a password through the installer or `passwd` in the installed system before relying on the display manager or sudo. The configuration retains password-required sudo and disables SSH; plan local console access.

- Establish networking interactively with NetworkManager; restore Wi-Fi/VPN credentials privately.
- Log into application accounts, GitHub, Steam, Mullvad and Flatpak applications as needed.
- Restore personal files, MPD music, Steam libraries and locally imported Ollama models separately.
- Obsidian: install the Local REST API community plugin, select a private vault, create credentials and a trusted local certificate, then set up the private environment file described in `PRIVACY.md`.
- Select a redistributable or personal wallpaper locally. None is bundled.
- The Flatpak service installs the declared applications after networking is available; this can take time and is not pinned to exact Flatpak commits.

## User files and backups

Existing live files were not modified by this migration. Future activation uses existing NixOS `L+` tmpfiles rules for Hyprland, Ghostty, GTK cursor settings and rmpc: **these replace destination files/symlinks**. Back up those paths before the first deployment on another machine. Ambxst JSON/binds and GTK/Qt color seeds instead use `C` rules, which leave existing destinations untouched. Edit and deliberately copy revised seeds when you want them applied to an existing account; a normal rebuild is not a theme reset.

There is no separate Home Manager command. To use the public example directly, first supply correct hardware/account settings and review all options; its flake output is named `workstation`.

On the original machine, an existing Ambxst general.json store symlink is also left untouched by seeding. To make it writable later, back it up and replace it deliberately with a regular copy; this audit did not alter that live symlink.
