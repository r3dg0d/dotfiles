{ inputs, ... }:
{
  imports = [ inputs.nix-flatpak.nixosModules.nix-flatpak ];

  # services.flatpak.enable is already set in modules/desktop.nix; this
  # only adds the declarative remote/package-list layer on top of it.
  services.flatpak.remotes = [
    {
      name = "flathub";
      location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    }
  ];

  # App IDs verified against the live Flathub remote (`flatpak search`) at
  # write time, not guessed:
  services.flatpak.packages = [
    "io.github.kolunmi.Bazaar" # Bazaar
    "io.freetubeapp.FreeTube" # FreeTube
    "org.prismlauncher.PrismLauncher" # PrismLauncher
    "dev.vencord.Vesktop" # Vesktop
  ];
}
