{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # Same revision and locked dependency graph as the existing user-profile install.
  ambxst = inputs.ambxst;
  system = pkgs.stdenv.hostPlatform.system;
  originalDefault = ambxst.packages.${system}.default;

  # Ambxst's own launcher points FONTCONFIG_PATH at a directory containing
  # only a conf.d snippet with no top-level fonts.conf (see
  # nix/packages/default.nix's fontconfigConf) — not a valid fontconfig
  # root, so it never actually registers anything, including its own
  # bundled Phosphor Icons font. Confirmed live: icons that use Phosphor
  # glyphs (the toolbox tray, etc.) were rendering as raw codepoint text
  # ("E3 FE") instead of the icon shape. Registering the exact same font
  # package through the normal system fontconfig path (already used for
  # nerd-fonts.jetbrains-mono in configuration.nix) fixes lookup without
  # touching Ambxst's launcher script or its other bundled fonts.
  phosphorIcons = pkgs.callPackage "${ambxst}/nix/packages/phosphor-icons.nix" { };

  # Ambxst's own recorder (pkg/svc/recorder/service.go) execs
  # "gpu-screen-recorder" with no "-fallback-cpu-encoding" flag. On this
  # machine the NVIDIA driver only exposes NVENC API 13.0 while
  # gpu-screen-recorder 6.1.1 requires 13.1 (verified: recordings exit
  # immediately with "no video encoder was specified" until that flag is
  # added — see modules/screen-recorder.nix). A PATH-priority fix doesn't
  # reach this: Ambxst's own launcher script prepends its bundled
  # Ambxst-env/bin (which includes its own private, unwrapped
  # gpu-screen-recorder) ahead of everything else, including
  # /run/current-system/sw/bin, no matter how it's installed. So this
  # patches the actual arg list at the source, in a local overrideAttrs on
  # top of the exact pinned flake revision above (not a fork, not a
  # different revision).
  # Separately, "ambxst reload" reliably leaves axctl dead: verified live
  # that every reload spawns axctl (compositor/proc.go's startDaemon) but
  # it exits immediately (defunct), because the previous axctl instance
  # hadn't actually released /run/user/*/axctl.sock yet — a shutdown-vs-
  # respawn race, not a config problem (manually killing any stale axctl
  # and removing the socket right before respawning it fixed it every
  # time in testing). Everything that talks to axctl (window/workspace/
  # monitor state, and therefore anything gated on monitor info, e.g.
  # screenshot capture) silently breaks until it's manually restarted, so
  # this makes startDaemon() defensively clear both before spawning.
  patchedBackend = ambxst.packages.${system}.backend.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
            substituteInPlace pkg/svc/recorder/service.go \
              --replace-fail 'args = append(args, "-o", outPath)' \
                              'args = append(args, "-fallback-cpu-encoding", "yes", "-o", outPath)'
            substituteInPlace pkg/svc/compositor/proc.go \
              --replace-fail 'func (m *Manager) startDaemon() error {' \
                              'func (m *Manager) startDaemon() error {
      	_ = exec.Command("pkill", "-9", "-f", "axctl.*daemon").Run()
      	_ = os.Remove(axctlSocketPath())'
    '';
  });

  # Byte-identical to upstream's own "ambxst" launcher script (AMBXST_QS,
  # AMBXST_SHELL, PATH/QML*_IMPORT_PATH/FONTCONFIG_PATH exports, all
  # untouched) except its final exec line now targets patchedBackend.
  # Provides *only* bin/ambxst: an earlier version of this file looped
  # over every file in originalDefault/bin (170+ bundled tools — gsr-cli,
  # ping, matugen, fuzzel, quickshell, kitty, tesseract, ...) and
  # re-symlinked all of them at hiPrio, which nondeterministically
  # collided with other hiPrio packages (notably modules/screen-
  # recorder.nix's own gpu-screen-recorder wrapper, and iputils' ping) —
  # each collision was silently "resolved" by whichever path Nix happened
  # to process first. That's the likely cause of anything that looked
  # broken/inconsistent after that change. Every file other than
  # bin/ambxst now comes from exactly one place: originalDefault.
  patchedLauncher = pkgs.runCommand "ambxst-recorder-fallback-patched" { } ''
    mkdir -p "$out/bin"
    sed -E 's|^exec .*/bin/ambxst "\$@"$|exec ${patchedBackend}/bin/ambxst "$@"|' \
      "${originalDefault}/bin/ambxst" > "$out/bin/ambxst"
    chmod +x "$out/bin/ambxst"
  '';
in
{
  # patchedLauncher wins only the bin/ambxst collision (hiPrio); every
  # other file (share/fonts, lib/qt-6/qml, share/applications/
  # ambxst.desktop, and the rest of Ambxst-env's bundled tools, including
  # the unwrapped gpu-screen-recorder it's never actually reached at
  # anymore) still comes from originalDefault alone. Keep bundled
  # utilities from shadowing the host's explicitly selected tools.
  environment.systemPackages = [
    (lib.hiPrio patchedLauncher)
    (lib.setPrio 20 originalDefault)
  ];
  fonts.packages = [ phosphorIcons ];
  # Keep the one existing hyprland.start callback; do not import upstream startup modules.
}
