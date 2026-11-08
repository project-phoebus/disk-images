#!/usr/bin/env bash
# First boot of the SR10.2 DN3500 volume built by build_sr10.2_dn3500.sh:
# creates the node's registry, location-broker database and daemon markers
# with the SR10.2 tools, on the node itself, under MAME (the DN3500's MD7C
# PROM boots the volume, driven by the kernel repo's harness,
# domain_os/tools/mame_boot_dn3500.py, on the keyboard and display).
#
# The SR10.2 tapes ship no registry: rgy_create(8) builds one on a running
# node, and the daemons /etc/rc starts are enabled by stub files in
# /etc/daemons (as for the sau2 DN300 volume, scripts/first_boot_sr10.2_dn300.sh
# there).  The harness types:
#
#   Return                                at power on, in Service mode: the
#                                         keyboard is the console
#   ex domain_os                          the PROM's `>' prompt: load /sau7/domain_os
#   sh                                    the Phase II `)' prompt: a
#                                         single-process shell; it asks to log in
#   user.none.none, empty password        the only login without a registry
#   /install/tools/rgy_create             master registry in /sys/registry/rgy_data
#   crf /etc/daemons/llbd                 /etc/rc starts llbd, glbd, rgyd
#   crf /etc/daemons/glbd
#   crf /etc/daemons/rgyd
#   /etc/server /etc/ncs/llbd             glbd needs a running llbd
#   /etc/ncs/glbd -create -first          first GLB replica; it then serves,
#   ^C (after 40 s)                       so quit it
#   ^D                                    leave the shell
#   shut                                  Phase II: flush and dismount cleanly
#
# Every reserved account rgy_create makes (root, user, admin, ...) has the
# password -apollo-.  The next boot (`go') starts llbd, glbd and rgyd, and
# /etc/rc.user netman, the diskless node boot server.
#
# The harness sees the console only through the PROM's character routine, so
# only the PROM's output; once the kernel runs, each line is typed when the
# CPU idles (after at least --wait frames), and the result is checked on the
# volume afterwards with apollofs: the registry, the daemon markers, the GLB
# database, and a clean dismount (the LV label's mounted flag, 0xCE, clear).
#
# usage: first_boot_sr10.2_dn3500.sh <image.awd> [work dir]
#   The image is modified in place: the kernel writes it, so afterwards it IS
#   the finished volume.  Needs the kernel repo (DOMAIN_OS, default
#   ~/src/domainos-archeology/source/domain_os) for the harness and MAME, and
#   the SR10.2 SAU7 kernel's link map (SR102, the release root, default the
#   cache scripts/unpack_sr10.2.sh fills) for its symbols, and apollofs
#   (APOLLOFS, or scripts/install_apollofs.sh's).  The label's last valid time
#   is set first (the harness's --clean-volume), so the kernel accepts the
#   harness's 1991 calendar without asking.
set -euo pipefail
IMG="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
WORK="${2:-$(dirname "$IMG")/first_boot}"
DOMAIN_OS="${DOMAIN_OS:-$HOME/src/domainos-archeology/source/domain_os}"
SR102="${SR102:-$("$(dirname "$0")/../../scripts/unpack_sr10.2.sh")}"
SAU7="$SR102/install/ri.apollo.os.v.10.2/sau7"
AF="${APOLLOFS:-$("$(dirname "$0")/../../scripts/install_apollofs.sh")}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"

cd "$DOMAIN_OS"
python3 tools/mame_boot_dn3500.py \
    --map "$SAU7/domain_os.map" \
    --hard "$IMG" --clean-volume --service --ram 16M \
    --out-dir "$WORK/run" --frames 250000 --finish-after 4000 \
    --wait '1200!'  --type '\r' \
    --expect '>'    --type 'ex domain_os\r' \
    --wait 600      --type 'sh\r' \
    --wait 600      --type 'user.none.none\r' \
    --wait 600      --type '\r' \
    --wait 600      --type '/install/tools/rgy_create\r' \
                    --type 'crf /etc/daemons/llbd\r' \
                    --type 'crf /etc/daemons/glbd\r' \
                    --type 'crf /etc/daemons/rgyd\r' \
                    --type '/etc/server /etc/ncs/llbd\r' \
                    --type '/etc/ncs/glbd -create -first\r' \
    --wait '2400!'  --type '\x03' \
                    --type '\x04' \
    --wait 600      --type 'shut\r' \
    > "$WORK/harness.out" 2>&1 || true

fail() { echo "first boot: $*; see $WORK/harness.out and $WORK/run" >&2; exit 1; }
"$AF" -i "$IMG" list /sys/registry/rgy_data > /dev/null 2>&1 || fail "no registry (/sys/registry/rgy_data)"
for d in llbd glbd rgyd; do
    "$AF" -i "$IMG" list /sys/node_data/etc/daemons/$d > /dev/null 2>&1 || fail "no daemon marker $d"
done
for g in glb.e glb.p; do
    "$AF" -i "$IMG" list /sys/node_data/$g > /dev/null 2>&1 || fail "glbd did not create its database ($g)"
done
mounted=$(dd if="$IMG" bs=1 skip=$((1056 + 32 + 0xCE)) count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
[ "$mounted" = 0000 ] || fail "no clean shutdown (the volume is still marked mounted)"
echo "first boot done: $IMG"
