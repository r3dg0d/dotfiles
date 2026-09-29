{ lib, rustPlatform, fetchFromGitHub }:
rustPlatform.buildRustPackage rec {
  pname = "matrix";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "r3dg0d";
    repo = "matrix";
    rev = "45a9a7d6c36d0563eee401189e2a9ac311a63026";
    hash = "";
  };

  cargoLock.lockFile = ./Cargo.lock;

  meta = with lib; {
    description = "Realtime Matrix-style digital rain for the terminal";
    homepage = "https://github.com/r3dg0d/matrix";
    license = licenses.mit;
    mainProgram = "matrix";
    platforms = platforms.unix;
  };
}
