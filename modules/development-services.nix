{ config, pkgs, ... }:

let
  home = config.workstation.homeDirectory;
  user = config.workstation.username;
in
let python = import ../dev/python.nix { inherit pkgs; };
in {
  virtualisation.docker.enable = true;
  users.users.${user}.extraGroups = [ "docker" ];
  environment.systemPackages = [ pkgs.docker-compose ];
  # Refresh the existing venv against the exact Python environment at every rebuild.
  system.activationScripts.developmentVenv = {
    deps = [ "users" ];
    text = ''
      ${pkgs.coreutils}/bin/install -d -o ${user} -g users ${home}/.venvs
      ${pkgs.util-linux}/bin/runuser -u ${user} -- ${python}/bin/python -m venv --upgrade --system-site-packages ${home}/.venvs/default
    '';
  };
}
