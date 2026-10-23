#!/usr/bin/env bash
# Co-op, custom avatars and per-peer cost: coop.sh OUT_DIR [PLAYERS, default 4]; --flat, a flat-screen visitor.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
exec python3 "$root/scripts/coop.py" "$@"
