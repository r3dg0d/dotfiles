{ pkgs }:
pkgs.mkShell {
  packages = with pkgs; [
    rustc
    cargo
    rustfmt
    clippy
    rust-analyzer
    pkg-config
    cmake
    ninja
  ];
  buildInputs = [ pkgs.openssl ];
  RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
}
