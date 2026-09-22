{ ... }:
let
  # Same pinning style as modules/ambxst.nix: pull one flake input via
  # builtins.getFlake without migrating this (non-flake) system to flakes.
  nix-flatpak = builtins.getFlake "github:gmodena/nix-flatpak/0f392e302963bce69787c495aa95ef1d50dda889?narHash=sha256-8wVBx1J5hR1DzUyzlrm2DkMXx7RJbATh3%2BR%2BqBBILlI%3D";
in {
  imports = [ nix-flatpak.nixosModules.nix-flatpak ];

  # services.flatpak.enable is already set in modules/desktop.nix; this
  # only adds the declarative remote/package-list layer on top of it.
  services.flatpak.remotes = [
    { name = "flathub"; location = "https://dl.flathub.org/repo/flathub.flatpakrepo"; }
  ];

  # App IDs verified against the live Flathub remote (`flatpak search`) at
  # write time, not guessed.
  # Vesktop (dev.vencord.Vesktop) removed 2026-09-21 — replaced by Equibop (nixpkgs).
  services.flatpak.packages = [
    "io.github.kolunmi.Bazaar"        # Bazaar
    "io.freetubeapp.FreeTube"         # FreeTube
    "org.prismlauncher.PrismLauncher" # PrismLauncher
    "net.rpcs3.RPCS3"                # RPCS3 (Flatpak; nixpkgs build ICE on this pin)
    # Hytale: not on Flathub as of writing; leave out pending a decision.
  ];
}
