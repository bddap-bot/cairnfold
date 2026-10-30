# The editor the scripts run as godot4, nixpkgs' Godot with scripts/engine.patch: tests, imports and the shader baker run
# the renderer the templates scripts/engine.sh builds carry.
{ pkgs ? import ./nixpkgs.nix {} }:
pkgs.godot_4_6.overrideAttrs (old: { patches = old.patches ++ [ ./scripts/engine.patch ]; })
