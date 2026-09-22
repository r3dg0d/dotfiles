{ pkgs, ... }:
let
  # Eden, the Switch 1 emulator derived from Yuzu and Sudachi.
  #
  # This installs upstream's official PGO build (packages/eden-pgo-bin.nix),
  # which upstream marks "Recommended" and claims is ~10-30% faster than the
  # standard build. nixpkgs' own pkgs.eden is the same 0.2.1 release built from
  # source, but as a generic GCC/LTO build with no PGO; switching back is a
  # one-line change here, and worth doing if a future PGO AppImage regresses.
  eden = pkgs.callPackage ../packages/eden-pgo-bin.nix { };

  # Display backend: XWayland, not native Wayland.
  #
  # This follows the current release rather than folklore. Eden 0.2.1 raises a
  # dialog on any Wayland session reading "Wayland is known to have significant
  # performance issues and mysterious bugs. It's recommended to use X11
  # instead." (src/yuzu/main_window.cpp, OnCheckGraphicsBackend), defaulting to
  # "Use X11". The official AppImage goes further and forces X11 itself, in
  # bin/wayland-is-broken.hook. The QT_QPA_PLATFORM=xcb default is applied in
  # the package wrapper; `QT_QPA_PLATFORM=wayland eden` still overrides it.

  # Upstream's controller rules, so Switch Pro / Joy-Con controllers are
  # accessible without root. The AppImage does not carry them, so they are
  # taken from the release source that nixpkgs already fetches. This is a
  # build-time reference only - the resulting derivation is just the one
  # rules file, and does not pull the nixpkgs eden build into the closure.
  edenUdevRules = pkgs.runCommand "eden-udev-rules" { } ''
    install -Dm444 ${pkgs.eden.src}/dist/72-yuzu-input.rules \
      $out/lib/udev/rules.d/72-yuzu-input.rules
  '';
in
{
  environment.systemPackages = [
    eden

    # Vulkan diagnostics (vulkaninfo, vkcube). Eden renders with Vulkan on the
    # RTX 4090; this is what verifies the driver is being picked up.
    pkgs.vulkan-tools
  ];

  services.udev.packages = [ edenUdevRules ];
}
