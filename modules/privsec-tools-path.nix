{ config, pkgs, ... }:
let
  home = config.workstation.homeDirectory;
  libstdcpp = "${pkgs.stdenv.cc.cc.lib}/lib";
  wrapLocal = name: pkgs.writeShellScriptBin name ''
    exec ${home}/.local/bin/${name} "$@"
  '';
  wrapPy = name: pkgs.writeShellScriptBin name ''
    export LD_LIBRARY_PATH="${libstdcpp}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec ${home}/.local/bin/${name} "$@"
  '';
in {
  environment.localBinInPath = true;

  environment.systemPackages = [
    (wrapLocal "macrandom")
    (wrapLocal "mullvadctl")
    (wrapLocal "metaclean")
    (wrapLocal "dnscheck")
    (wrapLocal "netidentity")
    (wrapLocal "fileshred")
    (wrapLocal "browserprivacy")
    (wrapLocal "opsec-check")
    (wrapLocal "fakeperson")
    (wrapLocal "deepfake")
    (wrapLocal "aivoice")
  ];
}
