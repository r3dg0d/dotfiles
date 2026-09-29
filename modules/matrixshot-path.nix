{ config, pkgs, lib, ... }:
let
  home = config.workstation.homeDirectory;
  projectsSrc = /. + "${home}/Projects/MatrixShot";
  packaged =
    if builtins.pathExists (projectsSrc + "/packaging/nix/package.nix")
    then pkgs.callPackage (projectsSrc + "/packaging/nix/package.nix") {
      matrixshotSrc = projectsSrc;
    }
    else null;
  wrap = name: pkgs.writeShellScriptBin name ''
    exec ${home}/.local/bin/${name} "$@"
  '';
in {
  # MatrixShot: real package from Projects when available; else ~/.local/bin
  # wrappers. `nixos-rebuild switch` required for system profile update.
  environment.systemPackages =
    if packaged != null then [
      packaged
      (wrap "keystroke-noise")
    ] else [
      (wrap "matrixshot")
      (wrap "matrixshot-preview")
      (wrap "matrixshot-edit")
      (wrap "matrixshot-rec-ui")
      (wrap "matrixshot-ui")
      (wrap "keystroke-noise")
    ];
}
