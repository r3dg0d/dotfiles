# Matrix Code Rain, the SDDM greeter theme this workstation logs in through.
#
# The theme is maintained as a standalone project and fetched by revision here,
# rather than vendored, so the published theme and the configuration that uses
# it cannot drift apart: https://github.com/r3dg0d/matrix-code-rain-sddm
#
# services.displayManager.sddm reads themes from
# /run/current-system/sw/share/sddm/themes, so adding this package to
# environment.systemPackages is the whole installation -- no files are copied
# into /usr/share, and the greeter rolls back with the generation.
{
  lib,
  runCommand,
  fetchFromGitHub,
  qt6,
}:
let
  themeId = "matrix-code-rain";

  src = fetchFromGitHub {
    owner = "r3dg0d";
    repo = "matrix-code-rain-sddm";
    rev = "a28b534052bd03315147503f8b4c203568f10d2a";
    hash = "sha256-TE9vY/mSZxNt0F9wobfZk1CK6gSEXOqsO6fsNiASbs8=";
  };
in
runCommand "sddm-theme-${themeId}"
  {
    nativeBuildInputs = [ qt6.qtdeclarative ];
    meta = {
      description = "Matrix-inspired SDDM theme with animated Katakana code rain";
      homepage = "https://github.com/r3dg0d/matrix-code-rain-sddm";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }
  ''
    themeDir=$out/share/sddm/themes/${themeId}
    install -d "$themeDir"
    cp -r ${src}/. "$themeDir/"
    chmod -R u+w "$themeDir"

    # Developer material: useful in the theme repository, dead weight in the
    # store copy the greeter loads.
    rm -rf "$themeDir/tests" "$themeDir/.qmllint.ini"

    # Fail the build rather than the login screen: a QML error here would
    # otherwise first appear as a blank greeter at the next boot.
    #
    # sddm, config, userModel and sessionModel are context properties the
    # greeter injects at runtime, so every theme trips "unqualified access";
    # that category is disabled and the rest are not.
    qmllint \
      -I ${qt6.qtdeclarative}/lib/qt-6/qml \
      -I "$themeDir" \
      --unqualified disable \
      "$themeDir"/*.qml "$themeDir"/components/*.qml
  ''
