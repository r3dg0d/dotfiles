{
  description = "A preserved Hyprland/Ambxst NixOS workstation";
  inputs = {
    nixpkgs.url = "https://releases.nixos.org/nixos/unstable/nixos-26.11pre1073009.ef34387ddd75/nixexprs.tar.xz";
    boo.url = "github:coder/boo/39245a70b2b3c66da3e5f47e80e84926d790863f";
    boo.inputs.nixpkgs.follows = "nixpkgs";
    durdraw.url = "github:durdraw/durdraw/bacad9c4c3254ca9ffc95122b899e1d3293b063c";
    durdraw.inputs.nixpkgs.follows = "nixpkgs";
    ambxst.url = "github:Axenide/Ambxst/d6a3b7207bdc9591d545ee6cac785446279a5a72?narHash=sha256-5FJ1%2BvvzGEF%2B4YOyUkOY5fCy07XGOx/xdHuxDiCHQZ0%3D";
    nix-flatpak.url = "github:gmodena/nix-flatpak/0f392e302963bce69787c495aa95ef1d50dda889?narHash=sha256-8wVBx1J5hR1DzUyzlrm2DkMXx7RJbATh3%2BR%2BqBBILlI%3D";
  };
  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      baseModules = [
        ./hosts/workstation/default.nix
        ./modules/workstation-apps.nix
        ./modules/workstation-hardening.nix
        ./modules/android-workstation.nix
        ./modules/obsidian-mcp.nix
      ];
      mkWorkstation =
        {
          modules ? [ ],
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = baseModules ++ modules;
        };
    in
    {
      lib = { inherit mkWorkstation; };
      nixosConfigurations.workstation = mkWorkstation {
        modules = [ ./hosts/workstation/hardware-configuration.nix ];
      };
      formatter.${system} = pkgs.nixfmt;
      devShells.${system}.default = import ./dev/shell.nix { inherit pkgs; };
      checks.${system}.native-config =
        pkgs.runCommand "workstation-native-config"
          {
            nativeBuildInputs = [
              pkgs.lua
              pkgs.python3
              pkgs.git
              pkgs.gitleaks
            ];
          }
          ''
            luac -p ${./config/hyprland.lua}
            python ${./scripts/check-json.py} ${./config}
            python ${self}/scripts/test-privacy-scan.py
            python ${self}/scripts/privacy-scan.py
            gitleaks dir ${self} --config ${./.gitleaks.toml} --redact --no-banner
            touch $out
          '';
    };
}
