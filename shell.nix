{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  packages = [ pkgs.godot_4 pkgs.xorg.xorgserver pkgs.xorg.xauth (pkgs.python3.withPackages (p: [ p.numpy ])) pkgs.vorbis-tools pkgs.vulkan-loader ];
}
