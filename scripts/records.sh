#!/usr/bin/env bash
# Fails when a perf record added since BASE (default origin/main) names a build main never ran: records.sh [BASE]. A
# record of a commit BASE holds, landing with no change of its own to game, scenes, engine or build scripts, names what
# was measured however main moved since, so a long bench of a landed commit lands beside other game landings. Any other
# record's build must equal the working tree in those: one benched on a working commit and then rebased onto a main
# that changed them, followed by a commit that did, or benched uncommitted and named for the commit under it, carries
# figures from a tree main never ran, so the bench is re-taken.
# records.sh --tree REVISION fails when the checkout's game, scenes, engine or build scripts are not REVISION's, so a
# bench refuses to run uncommitted work it would name for the commit under it.
set -euo pipefail
cd "$(dirname "$0")/.."
measured=(game demo '*.nix' scripts/{engine,export,stage,android,package,render,bench,pins}.sh scripts/engine.patch)
if [ "${1:-}" = --tree ]; then
  git diff --quiet "$2" -- "${measured[@]}" && [ -z "$(git ls-files --others --exclude-standard -- "${measured[@]}")" ] ||
    { echo "records: this checkout's game, scenes or engine are not $2's; commit them, or bench $2's tree" >&2; exit 1; }
  exit 0
fi
ref=${1:-origin/main}
git rev-parse -q --verify "$ref^{commit}" >/dev/null || { echo "records: no $ref to compare with"; exit 0; }
base=$(git merge-base "$ref" HEAD)
unchanged=0
git diff --quiet "$base" -- "${measured[@]}" && unchanged=1
stale=0
while read -r f; do
  [[ $f =~ ^perf/.*/[0-9]{8}T[0-9]{6}Z-([0-9a-f]{7,})\.json$ ]] || continue
  if ! built=$(git rev-parse -q --verify "${BASH_REMATCH[1]}^{commit}"); then
    echo "records: $f names ${BASH_REMATCH[1]}, which is no single commit here; bench the tree that lands"
    stale=1
  elif ! { [ $unchanged = 1 ] && git merge-base --is-ancestor "$built" "$ref"; } &&
    ! git diff --quiet "$built" -- "${measured[@]}"; then
    echo "records: $f measured $built, whose game, scenes or engine differ from the tree that lands; bench that tree, or land the change and record a bench of it alone"
    stale=1
  fi
done < <(git diff --name-only --no-renames --diff-filter=A "$base" -- perf
  git ls-files --others --exclude-standard -- perf)
exit "$stale"
