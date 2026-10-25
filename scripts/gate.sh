#!/usr/bin/env bash
# Runs what AGENTS.md says a change owes before it lands, for the diff from BASE (default origin/main) to the working
# tree: gate.sh [BASE]. Every change owes test.sh, a changed shell script shellcheck, a change to World, Commands or a
# tool coop.sh, and a change to what scripts/android.sh builds from both APKs.
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
  echo "gate: scripts/coop.sh"
  nix-shell --run "scripts/coop.sh $out/coop"
fi
if owes '^(android\.nix|scripts/(android|android-template|export|notices|pins)\.sh|scripts/(android-notices\.gradle|android-template\.patch|notices\.py)|game/(project\.godot|export_presets\.cfg|android/.*))$'; then
  for target in quest lepton; do
    echo "gate: scripts/android.sh $target"
    nix-shell android.nix --run "scripts/android.sh $target $out/$target.apk"
  done
fi
echo "gate: ok"
