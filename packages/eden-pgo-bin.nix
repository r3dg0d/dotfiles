{ lib, stdenvNoCC, fetchurl, dwarfs, makeWrapper }:

# Eden, the official upstream PGO Linux build.
#
# Upstream distributes Linux builds only as AppImages. This is the
# amd64/clang/PGO variant, which upstream marks "Recommended" and claims runs
# ~10-30% faster than the standard GCC build. The other variants are for other
# CPUs: "legacy" is pre-Haswell, "steamdeck" is Zen 2, "rog-ally" is Zen 4.
# An i9-14900K wants plain amd64.
#
# This is NOT a normal AppImage: it is packed with uruntime + DwarFS, not
# squashfs, so nixpkgs' appimageTools (which shells out to unsquashfs) cannot
# read it at all. dwarfsextract unpacks it directly instead, which also means
# no FUSE, no appimage-run, and no bubblewrap layer at runtime.
#
# The payload uses `sharun`: it carries its own ld.so, glibc 2.43, Qt and Mesa,
# and relocates itself at startup. So the binaries are deliberately left alone
# here - no autoPatchelf, no RPATH shrinking, no stripping. Patching them would
# fight sharun and break the bundle.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "eden-pgo-bin";
  version = "0.2.1";

  src = fetchurl {
    url = "https://stable.eden-emu.dev/v${finalAttrs.version}/Eden-Linux-v${finalAttrs.version}-amd64-clang-pgo.AppImage";
    hash = "sha256-eii/mIsGSIMZiXIr26qQqzE3G0A4CBmYE+DqfIslum0=";
  };

  nativeBuildInputs = [ dwarfs makeWrapper ];

  unpackPhase = ''
    runHook preUnpack
    mkdir -p AppDir
    dwarfsextract --input $src --output AppDir
    runHook postUnpack
  '';
  sourceRoot = "AppDir";

  dontConfigure = true;
  dontBuild = true;
  # See the note above: sharun manages its own loader and library paths.
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec
    cp -a . $out/libexec/eden

    # The Vulkan loader inside the bundle is upstream's, not the nixpkgs one,
    # so it does not know about NixOS's driver location and only ships Mesa
    # ICDs - there is no NVIDIA ICD in the bundle, because it is proprietary.
    # sharun additionally pins VK_DRIVER_FILES to the bundle's own ICDs on
    # x86_64 unless SHARUN_ALLOW_SYS_VKICD is set. Both are corrected here, so
    # the loader reads NixOS's real ICD directory and finds the NVIDIA driver.
    # NixOS's nvidia_icd.json points at an absolute /nix/store library path,
    # so no LD_LIBRARY_PATH manipulation is needed.
    #
    # QT_QPA_PLATFORM: the bundle's own bin/wayland-is-broken.hook already
    # forces xcb (plus SDL_VIDEO_DRIVER=x11, GDK_BACKEND=x11). It is set here
    # too so the X11 choice survives upstream changing that hook.
    #
    # DISABLE_AUTO_UPDATES: the bundled self-updater.hook would fetch
    # appimageupdatetool and rewrite the AppImage in place. It already
    # self-disables because the store is read-only; this stops it reaching for
    # the network at all. Updates come from this expression instead.
    #
    # All --set-default, so any of it can still be overridden per-launch.
    makeWrapper $out/libexec/eden/AppRun $out/bin/eden \
      --set-default SHARUN_ALLOW_SYS_VKICD 1 \
      --set-default VK_DRIVER_FILES /run/opengl-driver/share/vulkan/icd.d \
      --set-default QT_QPA_PLATFORM xcb \
      --set-default DISABLE_AUTO_UPDATES 1

    install -Dm444 dev.eden_emu.eden.svg \
      $out/share/icons/hicolor/scalable/apps/dev.eden_emu.eden.svg

    install -Dm644 dev.eden_emu.eden.desktop \
      $out/share/applications/dev.eden_emu.eden.desktop
    substituteInPlace $out/share/applications/dev.eden_emu.eden.desktop \
      --replace-fail 'TryExec=eden' "TryExec=$out/bin/eden" \
      --replace-fail 'Exec=eden %f' "Exec=$out/bin/eden %f"

    runHook postInstall
  '';

  meta = {
    description = "Switch 1 emulator derived from Yuzu and Sudachi, official PGO Linux build";
    homepage = "https://eden-emu.dev/";
    downloadPage = "https://git.eden-emu.dev/eden-emu/eden/releases";
    license = with lib.licenses; [ gpl3Plus gpl2Plus lgpl3Plus ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "eden";
  };
})
