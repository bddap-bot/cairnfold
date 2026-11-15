#!/usr/bin/env bash
# records.sh [BASE]: fails when a perf record added since BASE (default origin/main) measured a build whose measured
# files differ from the working tree, unless BASE holds its commit and the record's own commit changes none (a landed
# commit's bench may land late).
# records.sh --tree REVISION: fails unless the checkout's measured files are REVISION's.
set -euo pipefail
cd "$(dirname "$0")/.."
measured=(game demo '*.nix' scripts/{engine,export,stage,android,package,render,bench,pins}.sh scripts/engine.patch)
tree_is() {
  git diff --quiet "$1" -- "${measured[@]}" && [ -z "$(git ls-files --others --exclude-standard -- "${measured[@]}")" ]
}
if [ "${1:-}" = --tree ]; then
  tree_is "$2" ||
    { echo "records: this checkout's game, scenes or engine are not $2's; commit them, or bench $2's tree" >&2; exit 1; }
  exit 0
fi
ref=${1:-origin/main}
git rev-parse -q --verify "$ref^{commit}" >/dev/null || { echo "records: no $ref to compare with"; exit 0; }
base=$(git merge-base "$ref" HEAD)
own_change() {
  local added
  added=$(git log -1 --diff-merges=first-parent --no-patch --diff-filter=A --format=%H "$base..HEAD" -- "$1")
  if [ -n "$added" ]; then
    git diff --quiet "$added^" "$added" -- "${measured[@]}" && return 1
  else
    tree_is HEAD && return 1
  fi
  return 0
}
stale=0
while read -r f; do
  [[ $f =~ ^perf/.*/[0-9]{8}T[0-9]{6}Z-([0-9a-f]{7,})\.json$ ]] || continue
  if ! built=$(git rev-parse -q --verify "${BASH_REMATCH[1]}^{commit}"); then
    echo "records: $f names ${BASH_REMATCH[1]}, which is no single commit here; bench the tree that lands"
    stale=1
  elif ! { git merge-base --is-ancestor "$built" "$ref" && ! own_change "$f"; } &&
    ! git diff --quiet "$built" -- "${measured[@]}"; then
    echo "records: $f measured $built, whose game, scenes or engine differ from the tree that lands; bench that tree, or land the change and record a bench of it alone"
    stale=1
  fi
done < <(git diff --name-only --no-renames --diff-filter=A "$base" -- perf
  git ls-files --others --exclude-standard -- perf)
exit "$stale"
