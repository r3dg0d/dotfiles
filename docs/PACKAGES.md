# Software inventory

This inventory derives from installed declarations, profiles, Flatpak enumeration and runtime service queries. Installation does not prove frequency of use; no browser history, shell history or personal documents were mined. `modules/` is the complete package source of truth.

| Category | Preserved software / owner |
| --- | --- |
| Desktop | Hyprland, Ambxst/Quickshell bundle, Ly, Nautilus, GTK portal, Bibata (`desktop`, `ambxst`, `cursor`) |
| Development | Rust/Cargo/Clippy/rustfmt/analyzer; GCC, Clang, clang-cl wrapper, LLVM tools, GDB/LLDB, CMake/Ninja/Meson/Make, MinGW, Python/pipx, Zig/ZLS, GitHub CLI |
| Android | Android Studio with composed SDK/emulator, adb tools, Gradle and gradle9; no system images or NDK |
| Terminal | Ghostty CRT theme, Bash, tmux, boo, fetch, ttyper, durdraw |
| Editors | Vim, Nano, Obsidian; no discovered Neovim/Helix config |
| Browsers / communication | Firefox, Thunderbird, Dino; Vesktop and FreeTube through Flatpak |
| Networking | NetworkManager, Mullvad, curl/wget, DNS and packet diagnostics, Wireshark |
| Multimedia | PipeWire, MPD/rmpc/mpc, mpv, ffmpeg, yt-dlp, GPU Screen Recorder, thumbnailers |
| Gaming | Steam/Proton, GameMode, Gamescope; PrismLauncher through Flatpak |
| Virtualization | KVM kernel support and Android emulator; no configured libvirt, distrobox or toolbox found |
| Security | nmap/masscan/rustscan, aircrack-ng/bettercap, hashcat/John, Metasploit, sqlmap, ffuf/gobuster, mitmproxy, Impacket, forensic and reverse-engineering tools, GnuPG/age, Lynis |
| OSINT | holehe; pinned custom yesitsme and TraxOsint wrappers |
| AI / ML | Ollama CUDA; Codex, Claude Code, OpenCode, Matcha; pinned Obsidian MCP client |
| Utilities | ripgrep, fd, jq/yq, fzf, bat, eza, lsof, patchelf, binutils, strace/ltrace |
| Fonts / theme | JetBrains Mono Nerd Font, Ambxst bundled fonts plus explicit Phosphor icons, Bibata-Modern-Classic, captured green GTK/Qt color seed |

Four Flatpak application IDs match the declarative list: Bazaar, FreeTube, PrismLauncher and Vesktop. Platform/codec/driver runtimes are Flatpak-managed dependencies and were not copied. Flatpak versions are not locked by flake.lock.

The normal user's Nix profile listed no entries at audit time. A local Codex symlink and a Bash PATH edit remain from an installer; Codex is already installed declaratively. Personal models, plugin downloads and game libraries remain imperative. Empty Kitty/mpv directories are not evidence of customized configuration and were not populated with invented defaults.

Questionable/dormant items were retained for review: alternate Hyprland layout bindings, example device settings, numerous overlapping security tools, and the existing axctl force-termination patch. No package was removed based on taste.
