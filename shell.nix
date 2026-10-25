{ pkgs ? import ./nixpkgs.nix {} }:
pkgs.mkShell {
  packages = [ pkgs.godot_4_6 pkgs.xorg.xorgserver pkgs.xorg.xauth (pkgs.python3.withPackages (p: [ p.numpy ])) pkgs.vorbis-tools pkgs.vulkan-loader pkgs.imagemagick pkgs.zip pkgs.unzip pkgs.ffmpeg pkgs.shellcheck ];
  CAIRNFOLD_LAVAPIPE = "${pkgs.mesa}/share/vulkan/icd.d/lvp_icd.x86_64.json";
  CAIRNFOLD_TITLE_FONT = "${pkgs.cinzel}/share/fonts/truetype/Cinzel-Bold.ttf";
}
