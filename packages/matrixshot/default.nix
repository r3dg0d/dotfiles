{ pkgs, lib ? pkgs.lib, matrixshotSrc }:
# Real package expression lives in the MatrixShot repo so GitHub stays the
# source of truth. This directory is the NixOS callPackage entrypoint.
pkgs.callPackage (matrixshotSrc + "/packaging/nix/package.nix") {
  inherit matrixshotSrc;
  # Optional runtime deps — nixpkgs provides these names.
}
