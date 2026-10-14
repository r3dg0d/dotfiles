# SDDM theme package: installs share/sddm/themes/deep-space (Qt 6, QtQuick only).
{ stdenvNoCC, lib }:
stdenvNoCC.mkDerivation {
  pname = "sddm-theme-deep-space";
  version = "1.0";
  src = ../config/sddm/deep-space;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    dir=$out/share/sddm/themes/deep-space
    mkdir -p $dir
    cp -r $src/. $dir/
    cp ${../wallpaper/deep-space-1440p.png} $dir/background.png
    runHook postInstall
  '';
  meta = {
    description = "deep-space SDDM theme by r3dg0d";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
