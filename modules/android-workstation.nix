{
  config,
  pkgs,
  lib,
  ...
}:
let
  sdk =
    (pkgs.androidenv.composeAndroidPackages {
      numLatestPlatformVersions = 1;
      buildToolsVersions = [ "latest" ];
      includeEmulator = true;
      includeSystemImages = false;
      includeNDK = false;
    }).androidsdk;
  gradle9 = pkgs.writeShellScriptBin "gradle9" ''
    exec ${pkgs.gradle_9}/bin/gradle "$@"
  '';
in
{
  nixpkgs.config.android_sdk.accept_license = true;
  users.users.${config.workstation.username}.extraGroups = [ "kvm" ];
  environment.systemPackages = [
    sdk
    pkgs.android-tools
    (pkgs.android-studio.withSdk sdk)
    pkgs.android-studio-tools
    pkgs.gradle
    gradle9
  ];
  environment.sessionVariables = {
    ANDROID_HOME = "${sdk}/libexec/android-sdk";
    ANDROID_SDK_ROOT = "${sdk}/libexec/android-sdk";
  };
}
