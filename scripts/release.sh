#!/usr/bin/env bash
# Builds every disk image, finished (built, then first-booted), compresses it
# with xz -9e, and uploads it with the .sha256 of the compressed file to the
# GitHub release for <tag>:
#
#   dn300_sr10.2.awd.xz   dn300_sr10.2.awd.xz.sha256    (sau2)
#   dn3500_sr10.2.awd.xz  dn3500_sr10.2.awd.xz.sha256   (sau7)
#   dn2500_sr10.2.hd.xz   dn2500_sr10.2.hd.xz.sha256    (sau9)
#
# The images are built in dist/<tag>/ from the checked-out tree, which must be
# clean and at <tag>, so the assets match the scripts the tag holds.  The
# release must already exist (gh release create <tag>); assets of the same
# name are replaced.  The first boots run under MAME; the whole run takes
# about ten minutes, most of it the DN3500 volume's build.
#
# usage: release.sh <tag>
#   NO_UPLOAD=1 builds the images without checking the tree or the release and
#   without uploading.  SOURCE_DATE_EPOCH defaults to 675734400 (1991-06-01
#   00:00 UTC), the time the README's images are built with.  Needs gh, logged
#   in, xz, and what the build and first-boot scripts need (README.md).
set -euo pipefail
TAG="${1:?usage: release.sh <tag>}"
TOP="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$TOP/dist/$TAG"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-675734400}"
log() { echo "release: $*" >&2; }

# Every check that can fail runs before the builds and first boots do.
command -v xz > /dev/null || { log "needs xz"; exit 1; }
if [ -z "${NO_UPLOAD:-}" ]; then
    cd "$TOP"
    [ -z "$(git status --porcelain)" ] || { log "the working tree has changes; commit or stash them"; exit 1; }
    git rev-parse -q --verify "refs/tags/$TAG" > /dev/null || git fetch -q origin "refs/tags/$TAG:refs/tags/$TAG" || {
        log "no tag $TAG, here or on origin"; exit 1; }
    [ "$(git rev-parse HEAD)" = "$(git rev-parse "$TAG^{commit}")" ] || {
        log "HEAD is not $TAG; check it out first (git checkout $TAG)"; exit 1; }
    gh release view "$TAG" > /dev/null || { log "no GitHub release $TAG; create it first (gh release create $TAG)"; exit 1; }
fi
SR102="$("$TOP/scripts/unpack_sr10.2.sh")"
export SR102

rm -rf "$OUT" && mkdir -p "$OUT"
sum=$(command -v sha256sum || echo "shasum -a 256")
assets=()
# sau  build script               first-boot script             image
for row in \
    "sau2 build_sr10.2_dn300.sh  first_boot_sr10.2_dn300.sh  dn300_sr10.2.awd" \
    "sau7 build_sr10.2_dn3500.sh first_boot_sr10.2_dn3500.sh dn3500_sr10.2.awd" \
    "sau9 build_sr10.2_dn2500.sh first_boot_sr10.2_dn2500.sh dn2500_sr10.2.hd"
do
    read -r sau build boot img <<< "$row"
    log "$sau: building $img"
    "$TOP/$sau/scripts/$build" "$SR102" "$OUT/$img" > "$OUT/$sau.build.log" 2>&1 || {
        log "$sau: build failed; see $OUT/$sau.build.log"; exit 1; }
    log "$sau: first boot"
    "$TOP/$sau/scripts/$boot" "$OUT/$img" "$OUT/first_boot_$sau" > "$OUT/$sau.first_boot.log" 2>&1 || {
        log "$sau: first boot failed; see $OUT/$sau.first_boot.log"; exit 1; }
    # The build's checksum is of the unbooted image; the assets carry the
    # compressed file's instead.
    rm -f "$OUT/$img.sha256"
    log "$sau: compressing $img"
    xz -9e -T0 -k -f "$OUT/$img"
    (cd "$OUT" && $sum "$img.xz" > "$img.xz.sha256")
    cat "$OUT/$img.xz.sha256" >&2
    assets+=("$OUT/$img.xz" "$OUT/$img.xz.sha256")
done

if [ -n "${NO_UPLOAD:-}" ]; then
    log "NO_UPLOAD set; built in $OUT"
    exit 0
fi
log "uploading to release $TAG"
gh release upload "$TAG" "${assets[@]}" --clobber
gh release view "$TAG" --json url --jq .url
