#!/usr/bin/env bash
# Installs a bundle into ~/cairnfold on a headset and points its Steam library VR shortcut at it:
# deploy.sh BUNDLE.tar.gz [SSH_OPTION...] SSH_HOST; exits 3 when the bundle fails its import, leaving the install as it was
set -euo pipefail
here=$(dirname "$0")
bundle=$1
shift
out=$(ssh "$@" 'set -e; rm -rf cairnfold.new; mkdir cairnfold.new; tar -xz -C cairnfold.new
  (cd cairnfold.new/cairnfold && mkdir log && bin/godot --headless --path game --import > log/import.log 2>&1 && ! grep -qE "SCRIPT ERROR|Parse Error|Compile Error|Failed to load" log/import.log) || { echo "the Godot import failed: $(tail -5 cairnfold.new/cairnfold/log/import.log)" >&2; rm -rf cairnfold.new; exit 3; }
  rm -rf cairnfold.prev; if [ -d cairnfold ]; then mv cairnfold cairnfold.prev; fi
  mv cairnfold.new/cairnfold cairnfold; rmdir cairnfold.new
  echo "installed $(cat cairnfold/REVISION)" >&2; echo "$HOME/cairnfold"' < "$bundle")
node "$here/shortcut.mjs" "${out##*$'\n'}" "$@"
