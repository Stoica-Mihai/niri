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

for name in niri niri-session; do
    if [ ! -f "$here/$name" ]; then
        echo "error: $name is missing next to this script" >&2
        exit 1
    fi
done

# Refuse to install a build that can't run here. Without this the failure surfaces later as a
# bare loader error, usually a glibc too old for the build.
if ! "$here/niri" --version >/dev/null 2>&1; then
    echo "error: this build does not run on your system:" >&2
    "$here/niri" --version 2>&1 | sed 's/^/    /' >&2
    echo >&2
    echo "  Yours: $(ldd --version | head -1)" >&2
    echo "  A binary cannot run on a glibc older than the one it was built against." >&2
    echo "  Either update your system, or build from source, which always matches:" >&2
    echo "    git clone https://github.com/Stoica-Mihai/niri && cd niri && ./build-fork.sh" >&2
    exit 1
fi

# Only escalate when the destination needs it. Done after the check above so a rejected install
# leaves nothing behind.
sudo=()
if ! mkdir -p "$prefix/bin" 2>/dev/null || [ ! -w "$prefix/bin" ]; then
    sudo=(sudo)
fi

installed=()
for name in niri niri-session; do
    "${sudo[@]}" install -Dm755 "$here/$name" "$prefix/bin/$name"
    installed+=("$prefix/bin/$name")
done

printf '>> installed:\n'
printf '     %s\n' "${installed[@]}"
printf '>> %s\n' "$("$prefix/bin/niri" --version)"

if [ "$prefix" = /usr/local ] && [ -x /usr/bin/niri ]; then
    echo ">> shadows the packaged $(/usr/bin/niri --version)"
fi

echo ">> log out and back in to start the new session"
