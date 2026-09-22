{ pkgs, lib, ... }:
let
  cross = pkgs.pkgsCross.mingwW64;
  mingw = import ../dev/mingw.nix { inherit pkgs; };
in {
  environment.systemPackages = with pkgs; [
    rustc cargo rustfmt clippy rust-analyzer pkg-config
    gcc (lib.hiPrio clang) clang-tools lldb lld gdb cmake ninja meson gnumake
    # The native Clang wrapper does not expose clang-cl; use the LLVM driver
    # directly for SDK-supplied Windows builds, without Linux wrapper flags.
    (pkgs.writeShellScriptBin "clang-cl" ''
      exec ${pkgs.llvmPackages.clang-unwrapped}/bin/clang-cl "$@"
    '')
    binutils patchelf strace ltrace file xxd
    (import ../dev/python.nix { inherit pkgs; }) pipx
    (lib.lowPrio mingw) (lib.lowPrio cross.stdenv.cc.bintools)

    # CLI dev tooling
    zig zls gh
    codex        # OpenAI Codex CLI (pkgs.codex in this revision)
    claude-code  # unfree; covered by the top-level nixpkgs.config.allowUnfree
    fetch        # areofyl/fetch animated terminal fetch tool
  ];
  environment.etc."nixos-dev/mingw-w64.cmake".text = ''
    set(CMAKE_SYSTEM_NAME Windows)
    set(CMAKE_SYSTEM_PROCESSOR AMD64)
    set(CMAKE_C_COMPILER ${mingw}/bin/x86_64-w64-mingw32-gcc)
    set(CMAKE_CXX_COMPILER ${mingw}/bin/x86_64-w64-mingw32-g++)
    set(CMAKE_RC_COMPILER ${cross.stdenv.cc.bintools}/bin/x86_64-w64-mingw32-windres)
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  '';
}
