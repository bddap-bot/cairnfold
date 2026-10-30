# The compilers scripts/engine.sh builds native templates with, the official templates' own (pins.sh), made runnable
# on NixOS: { linux-x64, linux-arm64, windows }, each a prefix whose bin/ holds the compiler.
{ pkgs ? import ./nixpkgs.nix {} }:
let
  pins = builtins.readFile ./scripts/pins.sh;
  pin = name: let m = builtins.match ".*\n${name}=\\(([^ ]+) ([0-9a-f]+)\\).*" pins; in
    pkgs.fetchurl { url = builtins.elemAt m 0; sha256 = builtins.elemAt m 1; };
  # Points the host's executables and libraries at nixpkgs' loader and C libraries, keeping their own $ORIGIN paths; the
  # target's sysroot and libraries, which link into the template, are left as they came.
  toolchain = name: src: relocate: pkgs.stdenv.mkDerivation {
    inherit name src;
    nativeBuildInputs = [ pkgs.patchelf pkgs.file ];
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    dontPatchELF = true;
    dontPatchShebangs = true;
    dontCheckForBrokenSymlinks = true;
    installPhase = ''
      cp -a . $out
      cd $out
      ${relocate}
      find bin lib $(test -d libexec && echo libexec) -type f -exec file {} + | grep -E ':.*ELF 64-bit .*x86-64.*dynamically linked' | cut -d: -f1 |
        while read -r f; do
          if patchelf --print-interpreter "$f" > /dev/null 2>&1; then
            patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$f"
          fi
          patchelf --add-rpath ${pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.stdenv.cc.libc pkgs.zlib pkgs.zstd ]} "$f"
        done
    '';
  };
in {
  linux-x64 = toolchain "godot-sdk-x86_64" (pin "godot_sdk_x86_64") "./relocate-sdk.sh";
  linux-arm64 = toolchain "godot-sdk-arm64" (pin "godot_sdk_arm64") "./relocate-sdk.sh";
  windows = toolchain "llvm-mingw" (pin "llvm_mingw") "";
}
