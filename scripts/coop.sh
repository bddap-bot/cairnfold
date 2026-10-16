#!/usr/bin/env bash
# Headless co-op, custom avatars and per-peer cost: coop.sh OUT_DIR [PLAYERS, default 4].
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
exec python3 "$root/scripts/coop.py" "$@"
