#!/usr/bin/env bash
# Checks the SR10.2 release cartridges in tapes/sr10.2/ and unpacks them into a
# local cache, for the build and first-boot scripts:
#
#   tapes/sr10.2/*.ct.gz           the cartridge images, as bitsavers has them,
#                                  downloaded by hand (README.md, "Downloading
#                                  the cartridges")
#   <cache>/sr10.2/tapes/*.ct      gunzipped
#   <cache>/sr10.2/release/        the four base cartridges (boot, std 1-3)
#                                  extracted with readct into one tree: the
#                                  release root the scripts read (install/,
#                                  sysboot, sys/types, ...)
#   <cache>/sr10.2/incr2/          the INCR2 patch cartridge (suid_exec for a
#                                  running node's /etc), extracted on its own;
#                                  not on the volumes
#   <cache>/sr10.2/manifest.tsv    `apollofs ctindex` of the four base
#                                  cartridges: the generators' --manifest
#
# Each step is skipped when its output is already there, so a second run only
# prints the release root.  It stops, listing them, if any cartridge is missing
# from tapes/sr10.2/, and stops if one doesn't match its checksum below.
#
# usage: unpack_sr10.2.sh
#   tapes/sr10.2/ and cache/ are at the top of this repository; SR10_2_TAPES
#   and DISK_IMAGES_CACHE override them.  Prints the release root on stdout;
#   progress goes to stderr.
#   Needs gunzip and Go, which runs readct at the commit pinned below and
#   builds apollofs (scripts/install_apollofs.sh); READCT and APOLLOFS name
#   binaries to use instead.
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
TAPES_DIR="${SR10_2_TAPES:-$TOP/tapes/sr10.2}"
CACHE="${DISK_IMAGES_CACHE:-$TOP/cache}"
mkdir -p "$TAPES_DIR" "$CACHE/sr10.2/tapes"
TAPES_DIR="$(cd "$TAPES_DIR" && pwd)"
DIR="$(cd "$CACHE/sr10.2" && pwd)"
BASE=https://bitsavers.org/bits/Apollo/Apollo_JRJ/SR10.2
READCT_MOD=github.com/domainos-archeology/readct@1d3d3ff21320f8fea6ac7476fe21fcb4b12c1f36

# sha256 of each .ct.gz; the base cartridges in extraction order, INCR2 last.
TAPES=(
    "e5354f39a152efb90e136b42291cc6a5f7655b07835959867b81359bfffbd659 017286-001.CRTG_STD_SFW_BOOT_1-REV.00-SYSTEM_RELEASE_VER_SR10.2-RAI"
    "e51daf7f00be2e60f985dda274490e332987bf47720cbff06316f439c70dc1cc 017287-001.CRTG_STD_SFW_1-REV.00-SYSTEM_RELEASE_VER_SR10.2-RAI"
    "9ba43e2927dcff40193c5f088e940e58501b252fe4a7d29eb1971dacf89dabd0 017287-002.CRTG_STD_SFW_2-REV.00-SYSTEM_RELEASE_VER_SR10.2-RAI"
    "1304b50c2e55878979b2981b205d9f2eb57c2d35d2ff3c1c8f877e6aaa40cda7 017287-003.CRTG_STD_SFW_3-REV.00-SYSTEM_RELEASE_VER_SR10.2-RAI"
    "644cce656f0d7abd9f4b9428286175aeace4d63d9199388b73096080c4623ef4 018777-001.CRTG_OS_INCR2_1.SR10.2-INCRA_2"
)
BASE_TAPES=4

sum=$(command -v sha256sum || echo "shasum -a 256")
readct() { if [ -n "${READCT:-}" ]; then "$READCT" "$@"; else go run "$READCT_MOD" "$@"; fi; }
log() { echo "unpack_sr10.2: $*" >&2; }

missing=()
for t in "${TAPES[@]}"; do
    name="${t#* }"
    [ -f "$TAPES_DIR/$name.ct.gz" ] || missing+=("$BASE/$name.ct.gz")
done
if [ ${#missing[@]} -gt 0 ]; then
    log "download these into $TAPES_DIR/ (README.md, \"Downloading the cartridges\"):"
    for u in "${missing[@]}"; do log "  $u"; done
    exit 1
fi

cts=()
for t in "${TAPES[@]}"; do
    hash="${t%% *}" name="${t#* }"
    gz="$TAPES_DIR/$name.ct.gz"
    [ "$($sum "$gz" | cut -d' ' -f1)" = "$hash" ] || { log "checksum mismatch: $gz"; exit 1; }
    ct="$DIR/tapes/$name.ct"
    [ -f "$ct" ] || { log "gunzipping $name.ct.gz"; gunzip -c "$gz" > "$ct.tmp"; mv "$ct.tmp" "$ct"; }
    cts+=("$ct")
done

# readct extracts into the current directory; extract into a scratch directory
# and rename it into place, so an interrupted run leaves nothing half-done.
extract() {
    local out="$1"; shift
    [ -d "$out" ] && return
    log "extracting into $out"
    rm -rf "$out.tmp" && mkdir "$out.tmp"
    (cd "$out.tmp" && readct x "$@" > "$out.log")
    mv "$out.tmp" "$out"
}
extract "$DIR/release" "${cts[@]:0:BASE_TAPES}"
extract "$DIR/incr2" "${cts[@]:BASE_TAPES}"

if [ ! -f "$DIR/manifest.tsv" ]; then
    log "indexing the base cartridges into manifest.tsv"
    AF="${APOLLOFS:-$("$TOP/scripts/install_apollofs.sh")}"
    "$AF" ctindex "${cts[@]:0:BASE_TAPES}" > "$DIR/manifest.tsv.tmp"
    mv "$DIR/manifest.tsv.tmp" "$DIR/manifest.tsv"
fi

echo "$DIR/release"
