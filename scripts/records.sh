#!/usr/bin/env bash
# Fails when a perf record added since BASE (default origin/main) names a build whose game, scenes or engine and build
# scripts differ from the working tree's: records.sh [BASE]. A record benched on a working commit and then rebased onto
# a main that changed those, or followed by a commit that did, carries figures from a tree main never ran, so the bench
# is re-taken on the tree that lands.
set -euo pipefail
cd "$(dirname "$0")/.."
git rev-parse -q --verify "${1:-origin/main}^{commit}" >/dev/null || { echo "records: no ${1:-origin/main} to compare with"; exit 0; }
measured=(game demo '*.nix' scripts/{engine,export,stage,android,package,render,bench,pins}.sh scripts/engine.patch)
stale=0
while read -r f; do
  [[ $f =~ ^perf/.*/[0-9]{8}T[0-9]{6}Z-([0-9a-f]{7,})\.json$ ]] || continue
  if ! built=$(git rev-parse -q --verify "${BASH_REMATCH[1]}^{commit}"); then
    echo "records: $f names ${BASH_REMATCH[1]}, which is no single commit here; bench the tree that lands"
    stale=1
  elif ! git diff --quiet "$built" -- "${measured[@]}"; then
    echo "records: $f measured $built, whose game, scenes or engine differ from the tree that lands; bench it"
    stale=1
  fi
done < <(git diff --name-only --no-renames --diff-filter=A "$(git merge-base "${1:-origin/main}" HEAD)" -- perf
  git ls-files --others --exclude-standard -- perf)
exit "$stale"
