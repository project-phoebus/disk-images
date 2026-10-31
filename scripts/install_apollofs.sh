#!/usr/bin/env bash
# Builds apollofs (https://github.com/project-phoebus/apollofs) at the commit
# pinned below into the cache, the first time, and prints its path; the build
# and unpack scripts run that binary unless APOLLOFS names another.
#
#   <cache>/bin/apollofs-<commit>
#
# usage: install_apollofs.sh
#   The cache is cache/ at the top of this repository; DISK_IMAGES_CACHE
#   overrides it.  Prints the binary's path on stdout.  Needs Go.
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${DISK_IMAGES_CACHE:-$TOP/cache}"
MOD=github.com/project-phoebus/apollofs
COMMIT=8688260683f39624ac5924e383ac30eb37f62295

mkdir -p "$CACHE/bin"
BIN="$(cd "$CACHE/bin" && pwd)/apollofs-$COMMIT"
if [ ! -x "$BIN" ]; then
    echo "install_apollofs: building $MOD@$COMMIT" >&2
    rm -rf "$BIN.tmp" && mkdir "$BIN.tmp"
    GOBIN="$BIN.tmp" go install "$MOD@$COMMIT"
    # Imports left at another module path build against that module instead.
    if go version -m "$BIN.tmp/apollofs" | grep -q '^[[:space:]]*dep[[:space:]].*/apollofs[[:space:]]'; then
        echo "install_apollofs: $MOD@$COMMIT imports another apollofs module:" >&2
        go version -m "$BIN.tmp/apollofs" | grep '/apollofs[[:space:]]' >&2
        rm -rf "$BIN.tmp"
        exit 1
    fi
    mv "$BIN.tmp/apollofs" "$BIN" && rmdir "$BIN.tmp"
fi
echo "$BIN"
