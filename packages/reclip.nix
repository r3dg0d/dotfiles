{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [ ps.flask ]);
in
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "reclip";
  version = "0-unstable-2026-07-10";

  src = pkgs.fetchFromGitHub {
    owner = "averygan";
    repo = "reclip";
    rev = "1d161d15a4fe93d9b3371377f0a421dc3e965b10";
    hash = "sha256-ffSd3Ao3jR0R2LR49gSgDix31rTgvTW8Qwcd2xMT1S4=";
  };

  nativeBuildInputs = [ pkgs.makeWrapper ];

  # app.py writes its staging directory next to itself. That path is read-only
  # in the store, so honour $RECLIP_DOWNLOAD_DIR instead; the wrapper points it
  # at the user's XDG cache. This is the only change to upstream code.
  postPatch = ''
    substituteInPlace app.py \
      --replace-fail \
        'DOWNLOAD_DIR = os.path.join(os.path.dirname(__file__), "downloads")' \
        'DOWNLOAD_DIR = os.environ.get("RECLIP_DOWNLOAD_DIR") or os.path.join(os.path.dirname(__file__), "downloads")'
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/reclip
    cp -r app.py static templates $out/share/reclip/

    install -Dm444 static/favicon.svg \
      $out/share/icons/hicolor/scalable/apps/reclip.svg

    makeWrapper ${python}/bin/python $out/bin/reclip-server \
      --add-flags "$out/share/reclip/app.py" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.yt-dlp
          pkgs.ffmpeg
        ]
      } \
      --run 'export RECLIP_DOWNLOAD_DIR="''${RECLIP_DOWNLOAD_DIR:-''${XDG_CACHE_HOME:-$HOME/.cache}/reclip/downloads}"' \
      --set-default HOST 127.0.0.1 \
      --set-default PORT 8899

    runHook postInstall
  '';

  meta = {
    description = "Self-hosted video and audio downloader with a web UI";
    homepage = "https://github.com/averygan/reclip";
    license = pkgs.lib.licenses.mit;
    mainProgram = "reclip-server";
    platforms = pkgs.lib.platforms.linux;
  };
})
