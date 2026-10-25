# Android toolchain for scripts/android.sh: nix-shell android.nix --run 'scripts/android.sh quest|lepton OUT.apk'
{ pkgs ? import ./nixpkgs.nix { config = { android_sdk.accept_license = true; allowUnfree = true; }; } }:
let
  buildTools = "35.0.1";
  ndk = builtins.head (builtins.match ".*android_ndk_version=([0-9.]+).*" (builtins.readFile ./scripts/pins.sh));
  sdk = (pkgs.androidenv.composeAndroidPackages {
    buildToolsVersions = [ buildTools ];
    platformVersions = [ "35" ];
    includeNDK = true;
    ndkVersions = [ ndk ];
    includeEmulator = false;
    includeSystemImages = false;
  }).androidsdk;
in
pkgs.mkShell {
  packages = [ pkgs.python3 pkgs.godot_4_6 pkgs.jdk17 sdk pkgs.unzip pkgs.curl pkgs.git pkgs.scons ];
  CAIRNFOLD_LAVAPIPE = "${pkgs.mesa}/share/vulkan/icd.d/lvp_icd.x86_64.json";
  ANDROID_HOME = "${sdk}/libexec/android-sdk";
  ANDROID_BUILD_TOOLS = buildTools;
  JAVA_HOME = pkgs.jdk17.home;
}
