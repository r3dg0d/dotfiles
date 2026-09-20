# The host banner, printed once per interactive terminal.
#
# Everything in it that cannot change without a rebuild is substituted at build
# time, so the banner is a handful of `echo`s and one `figlet` call rather than
# a fetch tool shelling out to uname, the kernel and the display manager on
# every new prompt.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  green = "\\033[0;32m";
  bright = "\\033[1;92m";
  reset = "\\033[0m";

  label = key: value: ''
    printf '  ${green}%-10s${reset} ${bright}%s${reset}\n' "${key}" "${value}"
  '';

  # "matrix-code-rain" -> "Matrix Code Rain", so the banner follows the
  # configured theme instead of repeating its name as a literal.
  titleCase =
    id:
    lib.concatMapStringsSep " " (
      word: lib.toUpper (builtins.substring 0 1 word) + builtins.substring 1 (-1) word
    ) (lib.splitString "-" id);

  banner = pkgs.writeShellApplication {
    name = "host-banner";
    runtimeInputs = [
      pkgs.figlet
      pkgs.coreutils
    ];
    text = ''
      printf '${bright}'
      figlet -f small '${config.networking.hostName}'
      printf '${reset}'
      ${label "host" config.networking.hostName}
      ${label "os" "NixOS ${config.system.nixos.release} (${config.system.nixos.codeName})"}
      ${label "kernel" config.boot.kernelPackages.kernel.version}
      ${label "wm" "Hyprland ${config.programs.hyprland.package.version}"}
      ${label "greeter" "SDDM · ${titleCase config.services.displayManager.sddm.theme}"}
      ${label "shell" "bash"}
      echo
    '';
  };
in
{
  # Runnable by hand as `host-banner`, which is also how it is reused below.
  environment.systemPackages = [ banner ];

  # Interactive shells only (this init block is not read by non-interactive
  # ones), and then only when stdout is really a terminal -- an editor's or an
  # agent's captured shell should not have a banner in its output.
  #
  # HOST_BANNER_SHOWN is exported, so nested shells inside an already greeted
  # terminal stay quiet: the banner marks a new terminal, not every `bash` in
  # it.
  programs.bash.interactiveShellInit = lib.mkAfter ''
    if [ -z "''${HOST_BANNER_SHOWN:-}" ] && [ -t 1 ]; then
      export HOST_BANNER_SHOWN=1
      ${lib.getExe banner} || true
    fi
  '';
}
