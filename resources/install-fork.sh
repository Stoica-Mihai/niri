#!/usr/bin/env bash
# Installs this niri fork build. Shipped inside the release tarball as install.sh, alongside the
# files it installs.
#
#   ./install.sh [prefix]     prefix defaults to /usr/local
#
# The installed copies shadow the packaged niri in /usr/bin, because /usr/local/bin comes first in
# PATH and both niri.desktop and greetd invoke `niri-session` by name. Uninstall by removing them:
#
#   sudo rm /usr/local/bin/niri /usr/local/bin/niri-session
set -euo pipefail

prefix="${1:-/usr/local}"
here="$(cd "$(dirname "$0")" && pwd)"

# Only escalate when the destination actually needs it.
sudo=()
if ! mkdir -p "$prefix/bin" 2>/dev/null || [ ! -w "$prefix/bin" ]; then
    sudo=(sudo)
fi

installed=()
for name in niri niri-session; do
    src="$here/$name"
    if [ ! -f "$src" ]; then
        echo "error: $name is missing next to this script" >&2
        exit 1
    fi
    "${sudo[@]}" install -Dm755 "$src" "$prefix/bin/$name"
    installed+=("$prefix/bin/$name")
done

printf '>> installed:\n'
printf '     %s\n' "${installed[@]}"
printf '>> %s\n' "$("$prefix/bin/niri" --version)"

if [ "$prefix" = /usr/local ] && [ -x /usr/bin/niri ]; then
    echo ">> shadows the packaged $(/usr/bin/niri --version)"
fi

echo ">> log out and back in to start the new session"
