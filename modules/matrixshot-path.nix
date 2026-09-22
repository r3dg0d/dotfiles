{ config, pkgs, ... }:
let
  home = config.workstation.homeDirectory;
  wrap = name: pkgs.writeShellScriptBin name ''
    exec ${home}/.local/bin/${name} "$@"
  '';
in {
  # MatrixShot / KeystrokeNoise currently ship as user-built binaries under
  # ~/.local/bin. Display-manager sessions often lack that directory on PATH,
  # so Print Screen binds fail silently. Put stable wrappers on the system
  # profile; the real binaries stay in ~/.local/bin until packaged.
  environment.systemPackages = [
    (wrap "matrixshot")
    (wrap "matrixshot-preview")
    (wrap "matrixshot-edit")
    (wrap "keystroke-noise")
  ];
}
