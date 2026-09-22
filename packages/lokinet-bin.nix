{ stdenv, fetchurl, autoPatchelfHook, stdenvNoCC, lib }:
stdenvNoCC.mkDerivation {
  pname = "lokinet-bin";
  version = "0.9.14";
  src = fetchurl {
    url = "https://github.com/oxen-io/lokinet/releases/download/v0.9.14/lokinet-linux-amd64-v0.9.14.tar.xz";
    sha256 = "4097f96779a007abf35f37a46394eb5af39debd27244c190ce6867caf7a5115d";
  };
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  installPhase = ''
    install -Dm755 lokinet $out/bin/lokinet
    install -Dm755 lokinet-vpn $out/bin/lokinet-vpn
    install -Dm644 bootstrap.signed $out/share/bootstrap.signed
  '';
  meta = {
    description = "Official Lokinet binary release";
    homepage = "https://lokinet.org";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
  };
}
