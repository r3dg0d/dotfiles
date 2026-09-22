{ lib, stdenv, stdenvNoCC, fetchurl, autoPatchelfHook, makeWrapper
, alsa-lib, at-spi2-atk, at-spi2-core, atk, cairo, cups, dbus, expat
, glib, gtk3, libdrm, libGL, libgbm, libxkbcommon, nspr, nss, pango
, libX11, libXcomposite, libXdamage, libXext, libXfixes, libXrandr
, libxcb, systemd, qt5, qt6, xdg-utils }:
stdenvNoCC.mkDerivation {
  pname = "helium-bin";
  version = "0.17.0.1";
  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/0.17.0.1/helium-0.17.0.1-x86_64_linux.tar.xz";
    sha256 = "50238835e8896253d4af142a3032354119c1e6f7e777926c4530195c714ff3f5";
  };
  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
  buildInputs = [ stdenv.cc.cc.lib alsa-lib at-spi2-atk at-spi2-core atk cairo cups
    dbus expat glib gtk3 libdrm libGL libgbm libxkbcommon nspr nss pango
    libX11 libXcomposite libXdamage libXext libXfixes libXrandr libxcb systemd
    (lib.getLib qt5.qtbase) (lib.getLib qt6.qtbase) ];
  runtimeDependencies = [ libGL gtk3 ];
  dontWrapQtApps = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/helium $out/bin $out/share/applications
    cp -a . $out/lib/helium/
    makeWrapper $out/lib/helium/helium $out/bin/helium \
      --set CHROME_WRAPPER $out/bin/helium \
      --set CHROME_VERSION_EXTRA nixos \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libGL gtk3 ]}
    install -Dm644 product_logo_256.png $out/share/icons/hicolor/256x256/apps/helium.png
    cp helium.desktop $out/share/applications/helium.desktop
    substituteInPlace $out/share/applications/helium.desktop \
      --replace-fail 'Exec=helium' "Exec=$out/bin/helium"
    runHook postInstall
  '';
  meta = {
    description = "Helium web browser, official Linux binary";
    homepage = "https://helium.computer";
    license = with lib.licenses; [ gpl3Only bsd3 ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "helium";
  };
}
