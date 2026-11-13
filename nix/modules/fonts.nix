# r3dg0d's own fonts (NullType, Zerodot, Cellforge), installed from the prebuilt TTFs.
{ pkgs, ... }:
let
  mkFont = name: rev: hash: pkgs.stdenvNoCC.mkDerivation {
    pname = "${name}-font";
    version = "1.000";
    src = pkgs.fetchFromGitHub { owner = "r3dg0d"; repo = "${name}-font"; inherit rev hash; };
    dontBuild = true;
    installPhase = ''
      install -Dm644 -t $out/share/fonts/truetype fonts/ttf/*.ttf
      install -Dm644 -t $out/share/licenses/${name}-font OFL.txt
    '';
  };
  nulltype  = mkFont "nulltype"  "965612ac9d748857b28dfcda2d892727232ce32c" "sha256-FrPrh2TWrQYKOamkCf2SgOiToyNyF/gN7BJ65jqY2dM=";
  zerodot   = mkFont "zerodot"   "97c1655cf9515f917e7f7b2ef64b34b8e4020c64" "sha256-iFVPoGzEf696WiPh6XViBfe+WIAiBRGRMbcKvkAWr2Y=";
  cellforge = mkFont "cellforge" "da2bc523727b24e538fda4ec72aa4a60419843cb" "sha256-gYm2ucg/dWKcGq9+n7qDiunNW6sc7gGku46JtRTuSy0=";
in
{
  fonts.packages = [ nulltype zerodot cellforge ];
}
