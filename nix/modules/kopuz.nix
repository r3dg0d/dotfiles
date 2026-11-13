# Kopuz (music player: local library + Jellyfin/Navidrome/Subsonic/Spotify/etc).
# Not in nixpkgs; pinned to a specific commit of the upstream flake (verified it
# builds via its own Cachix cache — avoids a from-source Rust/webkitgtk compile).
# Bumped to v0.67.1 (7a3474e) on 2026-11-12.
{ config, lib, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  kopuz = (builtins.getFlake
    "github:temidaradev/kopuz/7a3474e9aa880f7ddc4e68a8846c48b23e13302c"
  ).packages.${system}.default;
in
{
  nix.settings = {
    substituters = [ "https://kopuz.cachix.org" ];
    trusted-public-keys = [ "kopuz.cachix.org-1:J2X3AnAYhKTJW5S3aCLoA1ckonQXVNZMQvhZA0YAufw=" ];
  };
  environment.systemPackages = [ kopuz ];
}
