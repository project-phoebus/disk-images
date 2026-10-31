#!/usr/bin/env bash
# First boot of the SR10.2 DN2500 volume built by build_sr10.2_dn2500.sh:
# creates the node's registry, location-broker database and daemon markers
# with the SR10.2 tools, on the node itself, under MAME (the DN2500's MD9 PROM
# boots the volume, driven by the kernel repo's harness,
# domain_os/tools/mame_boot_dn2500.py, on the serial console).
#
# The SR10.2 tapes ship no registry: rgy_create(8) builds one on a running
# node, and the daemons /etc/rc starts are enabled by stub files in
# /etc/daemons (as for the sau2 DN300 volume, scripts/first_boot_sr10.2_dn300.sh
# there).  The harness types:
#
#   BOOT                                  the PROM's prompt: boot the disk
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
# password -apollo-.  The next boot (`go') starts llbd, glbd and rgyd.
#
# usage: first_boot_sr10.2_dn2500.sh <image.hd> [work dir]
#   The image is modified in place: the kernel writes it, so afterwards it IS
#   the finished volume.  Needs the kernel repo (DOMAIN_OS, default
#   ~/src/domainos-archeology/source/domain_os) for the harness and MAME, and
#   the SR10.2 SAU9 kernel's link map (SR102, the release root, default the
#   cache scripts/unpack_sr10.2.sh fills) for its symbols.  The label's
#   last valid time is set first (the harness's --clean-volume), so the kernel
#   accepts the harness's 1991 calendar without asking.
set -euo pipefail
IMG="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
WORK="${2:-$(dirname "$IMG")/first_boot}"
DOMAIN_OS="${DOMAIN_OS:-$HOME/src/domainos-archeology/source/domain_os}"
SR102="${SR102:-$("$(dirname "$0")/../../scripts/unpack_sr10.2.sh")}"
SAU9="$SR102/install/ri.apollo.os.v.10.2/sau9"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"

cd "$DOMAIN_OS"
python3 tools/mame_boot_dn2500.py \
    --image "$SAU9/domain_os" --map "$SAU9/domain_os.map" \
    --hard "$IMG" --clean-volume --prom-boot --normal-mode --ram 16M \
    --work-dir "$WORK" --out-dir "$WORK/run" --port 4371 \
    --frames 400000 --stuck-frames 400000 --finish-on 'Shutdown successful' \
    --expect '\n>'         --send 'BOOT\r' \
    --expect 'Phase II'    --expect '\n)' --send 'sh\r' \
    --expect 'login: '     --send 'user.none.none\r' \
    --expect 'Password: '  --send '\r' \
    --expect '$ '          --send '/install/tools/rgy_create\r' \
    --expect '$ '          --send 'crf /etc/daemons/llbd\r' \
    --expect '$ '          --send 'crf /etc/daemons/glbd\r' \
    --expect '$ '          --send 'crf /etc/daemons/rgyd\r' \
    --expect '$ '          --send '/etc/server /etc/ncs/llbd\r' \
    --expect '$ '          --send '/etc/ncs/glbd -create -first\r' \
    --sleep 40             --send '\x03' \
    --expect '$ '          --send 'catf /sys/node_data/system_logs/glb_log\r' \
    --expect '$ '          --send '\x04' \
    --expect '\n)'         --send 'shut\r' \
    > "$WORK/harness.out" 2>&1 || true

CON="$WORK/run/console.txt"
tr -d '\r' < "$CON" | sed -n '/^)sh/,$p'
grep -q 'object glb created' "$CON" || { echo "first boot: glbd did not create its database" >&2; exit 1; }
grep -q 'Shutdown successful' "$CON" || { echo "first boot: no clean shutdown" >&2; exit 1; }
echo "first boot done: $IMG"
