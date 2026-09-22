{ config, pkgs, ... }:
{
  environment.systemPackages = [ pkgs.imv pkgs.xdg-utils ];
  environment.sessionVariables.BROWSER = "helium";
  system.activationScripts.defaultApplications = {
    deps = [ "users" ];
    text = ''
      ${pkgs.util-linux}/bin/runuser -u ${user} -- ${pkgs.python3}/bin/python \
        ${../user/set-default-applications.py} ${../user/default-applications.json}
    '';
  };
}
