#!/usr/bin/env bash
# Build + install this niri fork with a fork-marked version string.
# Usage: ./build-fork.sh [rev]   (rev defaults to 1)
# Version string = "<niri-base-tag>+mcs.<rev>", e.g. 26.04+mcs.1
set -euo pipefail
cd "$(dirname "$0")"

REV="${1:-1}"
BASE=$(git describe --tags --abbrev=0 --match 'v[0-9]*')
VER="${BASE#v}+mcs.${REV}"

echo ">> building niri fork $VER"
# build.rs does not track NIRI_BUILD_VERSION_STRING, so force the version
# source to recompile and bake the new string in.
touch src/utils/mod.rs
NIRI_BUILD_VERSION_STRING="$VER" cargo build --release

echo ">> installing to /usr/local/bin/niri (sudo)"
sudo install -Dm755 target/release/niri /usr/local/bin/niri

echo ">> installed: $(/usr/local/bin/niri --version)"
echo ">> log out / back in to activate the new binary"
