{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  packages = [ pkgs.godot_4 pkgs.xorg.xorgserver pkgs.xorg.xauth pkgs.python3 pkgs.vulkan-loader ];
}
