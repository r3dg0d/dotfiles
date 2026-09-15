{ pkgs }:
let
  yesitsmeSrc = pkgs.fetchFromGitHub {
    owner = "0x0be";
    repo = "yesitsme";
    rev = "64bea3936aa1a9ad29ac7eaebe93c5c4159ab1d3";
    sha256 = "09g4pcmcjynqhka3y739x9ikqs8v5xi2vp9f5v19r04zbgk5vpfy";
  };
  traxosintSrc = pkgs.fetchFromGitHub {
    owner = "N0rz3";
    repo = "TraxOsint";
    rev = "5a1be79ab3e7f8812d7928c571f6c69c83be7211";
    sha256 = "1i6sywa5j146b7z8jkkwwmd7xg3lf8nh4smpfgdg10m6jnjclv9w";
  };
  mcp-obsidianSrc = pkgs.fetchFromGitHub {
    owner = "MarkusPfundstein";
    repo = "mcp-obsidian";
    rev = "5ee0b84fa8319fd2fdf0db0ee1febb065e712a15";
    sha256 = "0g4fs40zc10bgbl4s7a3l9py3nlglp7c1n60xmscg91210zha9ay";
  };
  py = pkgs.python3Packages;
  scrape = py.buildPythonPackage {
    pname = "scrape-search-engine";
    version = "0.2.2";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/26/b4/88ca03f8feddc8766445538b34f8fb3d9c939616290e24c8b051e615f36b/scrape-search-engine-0.2.2.tar.gz";
      sha256 = "c1d6093053e54558d1a883608285e143363512df123699647a5353ee6e068c27";
    };
    pyproject = true;
    build-system = [ py.setuptools ];
    dependencies = [
      py.requests
      py.beautifulsoup4
    ];
    pythonImportsCheck = [ "ScrapeSearchEngine.SearchEngine" ];
  };
  osintPython = pkgs.python3.withPackages (p: [
    p.httpx
    p.requests
    p.beautifulsoup4
    p.colorama
    p.folium
    scrape
  ]);
in
{
  yesitsme = pkgs.writeShellApplication {
    name = "yesitsme";
    text = ''
      exec ${osintPython}/bin/python ${yesitsmeSrc}/yesitsme.py "$@"
    '';
  };
  traxosint = pkgs.writeShellApplication {
    name = "traxosint";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.iputils
    ];
    text = ''
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/traxosint"
      mkdir -p "$state/result"
      ln -sfn ${traxosintSrc}/useragents.txt "$state/useragents.txt"
      cd "$state"
      exec ${osintPython}/bin/python ${traxosintSrc}/traxosint.py "$@"
    '';
  };
  mcp-obsidian = py.buildPythonApplication {
    pname = "mcp-obsidian";
    version = "0.2.2";
    src = mcp-obsidianSrc;
    pyproject = true;
    build-system = [ py.hatchling ];
    dependencies = [
      py.mcp
      py.python-dotenv
      py.requests
    ];
    postPatch = ''
      substituteInPlace src/mcp_obsidian/obsidian.py \
        --replace-fail 'verify_ssl: bool = False' 'verify_ssl: bool = True' \
        --replace-fail 'self.verify_ssl = verify_ssl' 'self.verify_ssl = os.environ.get("OBSIDIAN_CA_BUNDLE") or verify_ssl'
    '';
    env.OBSIDIAN_API_KEY = "build-time-placeholder-not-a-secret";
    pythonImportsCheck = [ "mcp_obsidian" ];
  };
}
