#!/usr/bin/env bash
# gate.sh [BASE]: what AGENTS.md says a change since BASE (default origin/main) owes before it lands.
set -euo pipefail
cd "$(dirname "$0")/.."
base=$(git merge-base "${1:-origin/main}" HEAD)
mapfile -t changed < <(git diff --name-only --diff-filter=d "$base" --; git ls-files --others --exclude-standard)
shells=()
for f in "${changed[@]}"; do
  if [[ $f == *.sh ]] || head -n1 "$f" | grep -qE '^#!.*\b(ba)?sh\b'; then shells+=("$f"); fi
done
owes() { printf '%s\n' "${changed[@]}" | grep -qE "$1"; }
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
echo "gate: scripts/test.sh"
nix-shell --run scripts/test.sh
if [ ${#shells[@]} -gt 0 ]; then
  echo "gate: shellcheck ${shells[*]}"
  nix-shell --run "shellcheck ${shells[*]}"
fi
if owes '^game/src/(world|commands|[a-z_]+_tool)\.gd$'; then
  echo "gate: scripts/coop.py"
  nix-shell --run "scripts/coop.py $out/coop"
fi
if owes '^(android\.nix|godot\.nix|nixpkgs\.nix|scripts/with-jobs|scripts/(android|engine|export|notices|pins|stage)\.sh|scripts/(android-notices\.gradle|engine\.patch|notices\.py)|game/(project\.godot|export_presets\.cfg|android/.*))$'; then
  for target in quest lepton; do
    echo "gate: scripts/android.sh $target"
    nix-shell android.nix --run "scripts/android.sh $target $out/$target.apk"
  done
fi
if owes '^(shell\.nix|godot\.nix|toolchains\.nix|nixpkgs\.nix|scripts/with-jobs|LICENSE-.*|steam/.*|scripts/(package|engine|export|notices|pins|stage)\.sh|scripts/(engine\.patch|notices\.py)|game/(project\.godot|export_presets\.cfg))$'; then
  for target in linux-x64 linux-arm64 windows; do
    echo "gate: scripts/package.sh $target"
    nix-shell --run "scripts/package.sh $target $out/$target.pkg"
  done
fi
echo "gate: ok"
