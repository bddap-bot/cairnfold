# Android toolchain for scripts/android.sh: nix-shell android.nix --run 'scripts/android.sh OUT.apk'
{ pkgs ? import <nixpkgs> { config = { android_sdk.accept_license = true; allowUnfree = true; }; } }:
let
  buildTools = "35.0.0";
  sdk = (pkgs.androidenv.composeAndroidPackages {
    buildToolsVersions = [ buildTools ];
    platformVersions = [ "35" ];
    includeEmulator = false;
    includeSystemImages = false;
  }).androidsdk;
in
pkgs.mkShell {
  packages = [ pkgs.python3 pkgs.godot_4 pkgs.jdk17 sdk pkgs.unzip pkgs.curl pkgs.git ];
  ANDROID_HOME = "${sdk}/libexec/android-sdk";
  ANDROID_BUILD_TOOLS = buildTools;
  JAVA_HOME = pkgs.jdk17.home;
}
