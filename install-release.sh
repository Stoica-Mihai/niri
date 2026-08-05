#!/usr/bin/env bash
# Install a release of this fork: fetch the tarball, unpack it, run its installer.
#
#   ./install-release.sh                  latest release, into /usr/local
#   ./install-release.sh mcs-v6           a specific tag
#   ./install-release.sh latest /tmp/x    somewhere else (useful for testing)
#   ./install-release.sh --check          compare the release with what's running; no download
#
# --check exits 0 when they match, 1 when they differ, so it works in a shell conditional.
# NIRI_NO_GH=1 forces the plain-curl path, which needs no gh and no authentication.
set -euo pipefail

repo=Stoica-Mihai/niri

check_only=0
case "${1:-}" in
    --check | -c)
        check_only=1
        shift
        ;;
esac

tag="${1:-latest}"
prefix="${2:-/usr/local}"

use_gh=0
[ -z "${NIRI_NO_GH:-}" ] && command -v gh >/dev/null 2>&1 && use_gh=1

# Release metadata only — the asset name carries the version, so a check needs no download.
if [ "$use_gh" -eq 1 ]; then
    if [ "$tag" = latest ]; then
        meta=$(gh release view --repo "$repo" --json tagName,assets)
    else
        meta=$(gh release view "$tag" --repo "$repo" --json tagName,assets)
    fi
    read -r tag asset_name < <(printf '%s' "$meta" | python3 -c '
import json, sys
r = json.load(sys.stdin)
asset = next((a["name"] for a in r["assets"] if a["name"].endswith("-x86_64-arch.tar.gz")), "")
print(r["tagName"], asset)')
    asset_url=""
else
    if [ "$tag" = latest ]; then
        api="https://api.github.com/repos/$repo/releases/latest"
    else
        api="https://api.github.com/repos/$repo/releases/tags/$tag"
    fi
    read -r tag asset_name asset_url < <(curl -fsSL "$api" | python3 -c '
import json, sys
r = json.load(sys.stdin)
asset = next((a for a in r["assets"] if a["name"].endswith("-x86_64-arch.tar.gz")), None)
print(r["tag_name"], asset["name"] if asset else "-", asset["browser_download_url"] if asset else "-")')
fi

# niri-<version>-x86_64-arch.tar.gz
release_version=${asset_name#niri-}
release_version=${release_version%-x86_64-arch.tar.gz}

# What's actually in use: the running compositor if there is one, else the installed binary.
running_version=$(niri msg version 2>/dev/null | awk '/Compositor version/ { print $3 }' || true)
running_from="running compositor"
if [ -z "$running_version" ]; then
    running_from="installed binary"
    running_version=$("$prefix/bin/niri" --version 2>/dev/null | awk '{ print $2 }' || true)
fi
[ -n "$running_version" ] || { running_version="(none)"; running_from="not installed"; }

if [ "$check_only" -eq 1 ]; then
    printf 'release  %s  (%s)\n' "$release_version" "$tag"
    printf 'yours    %s  (%s)\n' "$running_version" "$running_from"
    if [ "$release_version" = "$running_version" ]; then
        echo "up to date"
        exit 0
    fi
    echo "differs — install with: $0 $tag"
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo ">> downloading $tag ($release_version)"
if [ "$use_gh" -eq 1 ]; then
    gh release download "$tag" --repo "$repo" --dir "$tmp" --pattern '*-x86_64-arch.tar.gz'
else
    curl -fSL --progress-bar -o "$tmp/niri.tar.gz" "$asset_url"
fi

echo ">> unpacking"
tar xzf "$tmp"/*.tar.gz -C "$tmp"

if [ ! -x "$tmp/install.sh" ]; then
    # Releases before mcs-v7 shipped the binary alone.
    echo "error: $tag has no install.sh; it predates self-installing tarballs." >&2
    echo "  Install by hand, or pick a newer release." >&2
    exit 1
fi

[ "$release_version" = "$running_version" ] && echo ">> note: $running_version is already in use"

"$tmp/install.sh" "$prefix"
