#!/usr/bin/env bash
# Installs a bundle on a headset over ssh into ~/cairnfold: deploy.sh SSH_HOST BUNDLE.tar.gz
set -euo pipefail
host=$1
bundle=$2
ssh "$host" 'set -e; rm -rf cairnfold.new; mkdir cairnfold.new; tar -xz -C cairnfold.new; rm -rf cairnfold.prev; [ -d cairnfold ] && mv cairnfold cairnfold.prev; mv cairnfold.new/cairnfold cairnfold; rmdir cairnfold.new; cat cairnfold/REVISION' < "$bundle"
