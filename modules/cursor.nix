{ pkgs, lib, ... }:
{
  # Bibata-Modern-Classic everywhere: Hyprland/Hyprcursor picks up
  # HYPRCURSOR_THEME/HYPRCURSOR_SIZE (set again in user/hyprland.lua via
  # hl.env so the compositor itself and its clients see it before any
  # session-manager env is read); XCURSOR_THEME/XCURSOR_SIZE cover
  # XWayland, Qt, and any app reading libXcursor directly. GTK gets its
  # own settings.ini (modules/user-desktop.nix) since some GTK apps
  # ignore XCURSOR_* env vars.
  environment.systemPackages = [
    pkgs.bibata-cursors
    # Without this, "gsettings set org.gnome.desktop.interface ..." fails
    # with "No schemas installed" — GTK4/libadwaita apps and the XDG
    # desktop portal's Settings interface (which sandboxed Flatpak apps
    # use instead of raw XCURSOR_* env vars) read the cursor theme from
    # here, not from Hyprland's env or GTK's settings.ini.
    pkgs.gsettings-desktop-schemas
  ];

  environment.sessionVariables = {
    XCURSOR_THEME = "Bibata-Modern-Classic";
    XCURSOR_SIZE = "24";
    HYPRCURSOR_THEME = "Bibata-Modern-Classic";
    HYPRCURSOR_SIZE = "24";
  };

  # Seed the default dconf profile ("user", dconf's implicit default when
  # $DCONF_PROFILE is unset) so org.gnome.desktop.interface resolves to
  # Bibata even for apps that only ask the portal/gsettings, without
  # bringing in Home Manager's `home.pointerCursor` (not used by this
  # config). Still overridable per-user via a normal `gsettings set`.
  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/interface" = {
        cursor-theme = "Bibata-Modern-Classic";
        cursor-size = lib.gvariant.mkInt32 24;
      };
    }
  ];
}
