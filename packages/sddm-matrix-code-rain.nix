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
  kdePackages,
}:
let
  themeId = "matrix-code-rain";

  # The greeter SDDM will actually start, and its Qt major version. Both are
  # asserted against the theme's metadata below.
  sddm = kdePackages.sddm;
  qtMajor = lib.versions.major qt6.qtbase.version;

  src = fetchFromGitHub {
    owner = "r3dg0d";
    repo = "matrix-code-rain-sddm";
    rev = "3b387f5e7f4268eb4e6b5281da3f9fb8e6a59d25";
    hash = "sha256-oIzC5HP0Yt/oD+aFTQjCjEy6WQk/5iboaDbGHCV34ho=";
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

    # SDDM's daemon reads SddmGreeterTheme/QtVersion from metadata.desktop and
    # defaults it to 5, then requires a `sddm-greeter` binary for that version.
    # This SDDM is Qt6-only (`sddm-greeter-qt6`), so a theme that omits the key
    # is skipped in favour of the built-in fallback -- and the greeter never
    # sees the theme, so `sddm-greeter-qt6 --test-mode` cannot catch it. The
    # only symptom is one line in the daemon's journal, which is how this was
    # found in the first place.
    declaredQt=$(sed -n 's/^QtVersion=//p' "$themeDir/metadata.desktop")
    if [ "$declaredQt" != "${toString qtMajor}" ]; then
      echo "metadata.desktop declares QtVersion='$declaredQt';" \
           "this SDDM needs ${toString qtMajor}." >&2
      exit 1
    fi
    if [ ! -x "${sddm}/bin/sddm-greeter-qt${toString qtMajor}" ]; then
      echo "${sddm} has no sddm-greeter-qt${toString qtMajor} for the theme to run in." >&2
      exit 1
    fi
  ''
