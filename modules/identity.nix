{ config, lib, ... }:
{
  options.workstation = {
    username = lib.mkOption {
      type = lib.types.strMatching "[a-z_][a-z0-9_-]*";
      default = "user";
      description = "Local workstation account, supplied by the private deployment.";
    };
    homeDirectory = lib.mkOption {
      type = lib.types.strMatching "/[a-zA-Z0-9_./-]+";
      default = "/home/${config.workstation.username}";
      description = "Absolute home directory; whitespace is unsupported by tmpfiles rules.";
    };
  };
  config = {
    users.users.${config.workstation.username}.home = config.workstation.homeDirectory;
    environment.localBinInPath = true;
  };
}
