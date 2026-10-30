{ pkgs ? import ./nixpkgs.nix {} }:
let toolchains = import ./toolchains.nix { inherit pkgs; }; in
pkgs.mkShell {
  packages = [ (import ./godot.nix { inherit pkgs; }) pkgs.xorg.xorgserver pkgs.xorg.xauth (pkgs.python3.withPackages (p: [ p.numpy ])) pkgs.vorbis-tools pkgs.vulkan-loader pkgs.imagemagick pkgs.zip pkgs.unzip pkgs.ffmpeg pkgs.shellcheck pkgs.scons pkgs.wayland-scanner ];
  CAIRNFOLD_LAVAPIPE = "${pkgs.mesa}/share/vulkan/icd.d/lvp_icd.x86_64.json";
  CAIRNFOLD_TITLE_FONT = "${pkgs.cinzel}/share/fonts/truetype/Cinzel-Bold.ttf";
  CAIRNFOLD_SDK_X64 = toolchains.linux-x64;
  CAIRNFOLD_SDK_ARM64 = toolchains.linux-arm64;
  CAIRNFOLD_MINGW = toolchains.windows;
}
