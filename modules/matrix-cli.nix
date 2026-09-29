{ pkgs, ... }:
{
  environment.systemPackages = [
    (pkgs.callPackage ../packages/matrix { })
  ];
}
