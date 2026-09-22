{ lib, stdenv, stdenvNoCC, fetchurl, dpkg, autoPatchelfHook, makeWrapper
, alsa-lib, at-spi2-atk, at-spi2-core, atk, cairo, cups, dbus, expat
, glib, gtk3, libdrm, libGL, libnotify, libuuid, libxkbcommon, mesa, nspr, nss
, pango, libX11, libXcomposite, libXdamage, libXext, libXfixes, libXrandr
, libXrender, libXtst, libxcb, systemd, libappindicator-gtk3 }:
stdenvNoCC.mkDerivation {
  pname = "lokinet-gui";
  version = "1.0.0";
  src = fetchurl {
    url = "https://deb.oxen.io/pool/main/l/lokinet-gui/lokinet-gui_1.0.0_amd64.deb";
    sha256 = "79b7f7ea08e21aefadcb204bd17a174c29fd08ac2d4e74ab34a343f7a8b9d25a";
  };
  nativeBuildInputs = [ dpkg autoPatchelfHook makeWrapper ];
  buildInputs = [ stdenv.cc.cc.lib alsa-lib at-spi2-atk at-spi2-core atk cairo cups
    dbus expat glib gtk3 libdrm libGL libnotify libuuid libxkbcommon mesa nspr nss
    pango libX11 libXcomposite libXdamage libXext libXfixes libXrandr libXrender
    libXtst libxcb ];
  runtimeDependencies = [ (lib.getLib systemd) libGL libappindicator-gtk3 ];
  unpackPhase = "dpkg-deb -x $src .";
  dontBuild = true;
  installPhase = ''
    mkdir -p $out/lib $out/bin $out/share
    cp -r opt/Lokinet-GUI $out/lib/lokinet-gui
    cp -r usr/share/applications usr/share/icons $out/share/
    makeWrapper $out/lib/lokinet-gui/lokinet-gui $out/bin/lokinet-gui \
      --add-flags "--disable-gpu --in-process-gpu" \
      --prefix PATH : ${lib.makeBinPath [ systemd ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}
    substituteInPlace $out/share/applications/lokinet-gui.desktop \
      --replace-fail /opt/Lokinet-GUI/lokinet-gui $out/bin/lokinet-gui \
      --replace-fail "Name=Lokinet-GUI" "Name=Lokinet GUI" \
      --replace-fail "Categories=Utility;" "Categories=Network;Utility;"
    echo "Keywords=Lokinet;Loki;VPN;" >> $out/share/applications/lokinet-gui.desktop
  '';
  meta = {
    description = "Official Lokinet control panel";
    homepage = "https://lokinet.org";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "lokinet-gui";
  };
}
