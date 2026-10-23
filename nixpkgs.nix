# nixos-25.11 at the rev bothouse's build timers resolved <nixpkgs> to, so their builds keep their store paths.
import (builtins.fetchTarball {
  url = "https://github.com/NixOS/nixpkgs/archive/71caefce12ba78d84fe618cf61644dce01cf3a96.tar.gz";
  sha256 = "1v4f4p1v444r56m6n4jdjc6i1wg3gx724l0rnr45j6cvn5hf5zf9";
})
