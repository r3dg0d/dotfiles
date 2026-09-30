{ config, pkgs, lib, ... }:
{
  environment.systemPackages = [ pkgs.imv pkgs.xdg-utils ];
  environment.sessionVariables.BROWSER = "helium";
  system.activationScripts.defaultApplications = {
    deps = [ "users" ];
    text = ''
      ${pkgs.util-linux}/bin/runuser -u ${lib.escapeShellArg config.workstation.username} -- \
        ${pkgs.coreutils}/bin/env XDG_CONFIG_HOME=${lib.escapeShellArg "${config.workstation.homeDirectory}/.config"} \
        ${pkgs.python3}/bin/python \
        ${../user/set-default-applications.py} ${../user/default-applications.json}
    '';
  };
}
