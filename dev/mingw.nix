{ pkgs }:
let
  cross = pkgs.pkgsCross.mingwW64;
  threads = cross.windows.mcfgthreads;
in
cross.stdenv.cc.overrideAttrs (old: {
  # Nix shells normally inject these dependency flags. System-wide commands
  # need them in their compiler wrapper to work outside a development shell.
  postFixup = (old.postFixup or "") + ''
    echo ' -isystem ${pkgs.lib.getDev threads}/include' >> "$out/nix-support/cc-cflags"
    echo ' -L${pkgs.lib.getLib threads}/lib' >> "$out/nix-support/cc-ldflags"
  '';
})
