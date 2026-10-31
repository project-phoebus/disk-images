#!/usr/bin/env python3
"""Generate build_sr10.2_dn2500.sh: the apollofs commands that build a native
SR10.2 disk for a DN2500 (sau9) from the SR10.2 release.

The volume's contents are the sau2 DN300 build's (the aegis_small template
holds every SAU's /sauN, /sau9 included); what differs is the disk: a SCSI
disk, which keeps no block headers, made with `apollofs invol --scsi`, and
written as a raw .hd image.  The DN2500 has no PEB, so /sys/peb2_microcode
goes on under its own name.

Inputs
  manifest   `apollofs ctindex` over the four SR10.2 cartridges (boot, std 1-3):
             one line per object with its tape volume/file, path, type and the
             VTOCE attribute image wbak recorded
  toc        install/toc/toc.apollo.ST0141.c: subcomponent -> (tape volume, file)
  template   install/templates/apollo/os.v.10.2/aa.aegis_small: the subcomponents
             an aegis-only "small" install moves into place (-rootaa)
  links      scripts/sr10.2_links.tsv: the soft links the install creates that
             are not tape objects (with provenance)

What goes on the volume
  * every object of every tape file the template selects, at its path inside
    install/ri.apollo.os.v.10.2 (the authorized-area layout is the node layout),
    with the attributes from its tape record;
  * the zero-size subcomponents of the template: /bscom (an empty directory),
    /bin, /dev, /tmp (links, from the links file); the *_link alternatives of
    subcomponents that are also selected as directories are not used;
  * the disked-node configuration the boot cartridge carries and the ri tapes do
    not: /sys/types (the type-name table), and the boot cartridge's links;
  * the boot cartridge's directories (empty ones such as `node_data/tmp and
    /sys/registry exist nowhere else);
  * sysboot via cpboot.
Directories take the boot cartridge's directory record (attributes and default
protections) when it has one for the same path, otherwise apollofs' default.
"""
import argparse
import re
import shlex
import sys

RI = 'install/ri.apollo.os.v.10.2/'
# Boot-cartridge files a disked node needs that no ri tape file has: the
# type-name table, and the registry-creation tool, which rgy_create(8) runs
# as /install/tools/rgy_create (a node's first boot runs it; the tapes carry
# no registry).
BOOT_EXTRA_FILES = ['sys/types', 'install/tools/rgy_create']

# Emulator workarounds: none.  (The DN300 build renames /sys/peb2_microcode
# because MAME's DN300 answers the PEB probe without emulating the board; the
# DN2500 has no PEB.)
RENAMES = {}

# The disk: Apollo's 200 MB internal SCSI disk for the Series 2500 (the
# configuration guide's typical DN2500), as cylinders/heads/sectors per track
# in 512-byte sectors.  400 x 16 x 63 = 403200 sectors (206,438,400 bytes) is
# a geometry MAME's raw-image loader guesses back from the image's size, so its
# READ CAPACITY and mode pages 3 and 4 report it.
SCSI_GEOMETRY = '400/16/63'

# Answers of the ov.<template> question file that decide whether a tape
# object belongs on the node.  "create_xapollo no": `node_data/etc/daemons/
# Xapollo is the marker /etc/rc starts the X server for instead of the DM;
# the boot cartridge's daemons directory has only README.
ANSWER_SKIPS = {('create_xapollo', 'no'): ['/sys/node_data/etc/daemons/Xapollo']}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--install-root', required=True, help='extracted SR10.2 tree (for the toc and template)')
    ap.add_argument('--template', default='aa.aegis_small')
    ap.add_argument('--links', required=True)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()

    root = args.install_root.rstrip('/') + '/'
    toc = {}
    for line in open(root + 'install/toc/toc.apollo.ST0141.c', errors='replace'):
        m = re.match(r'Subcomp\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+)', line)
        if m:
            toc[m.group(1)] = (int(m.group(2)), int(m.group(3)), int(m.group(4)))
    selected = []
    for line in open(root + 'install/templates/apollo/os.v.10.2/' + args.template):
        m = re.match(r'move ri.apollo.os.v.10.2 (\S+) -rootaa', line)
        if m:
            selected.append(m.group(1))
    tapefiles = {toc[s][:2]: s for s in selected if toc[s][0]}
    zero = [s for s in selected if toc[s][0] == 0]

    answers = {}
    for line in open(root + 'install/templates/apollo/os.v.10.2/' + args.template.replace('aa.', 'ov.', 1)):
        m = re.match(r'Answer\s+(\S+)\s+\d+\s+(\S+)', line)
        if m:
            answers[m.group(1)] = m.group(2)
    skip = set()
    for (q, a), paths in ANSWER_SKIPS.items():
        if answers.get(q) == a:
            skip.update(paths)

    files = []        # (dest, src, attrs, type, size)
    boot_dirs = {}    # path -> (attrs, extra)
    boot_files = {}
    for line in open(args.manifest):
        f = line.rstrip('\n').split('\t')
        vol, seq, label, kind, path, typ, size, attrs, extra = f[:9]
        vol, seq = int(vol), int(seq)
        if vol == 0:
            if kind == 'dir':
                boot_dirs['/' + path] = (attrs, extra)
            elif kind == 'file':
                boot_files[path] = (attrs, typ, int(size))
            continue
        if (vol, seq) not in tapefiles or kind != 'file' or not path.startswith(RI):
            continue
        dest = '/' + path[len(RI):]
        if dest in skip:
            continue
        dest = RENAMES.get(dest, dest)
        files.append((dest, path, attrs, typ, int(size), tapefiles[(vol, seq)]))
    for p in BOOT_EXTRA_FILES:
        attrs, typ, size = boot_files[p]
        files.append(('/' + p, p, attrs, typ, size, 'boot cartridge'))

    sysboot = [f for f in files if f[0] == '/sysboot']
    files = [f for f in files if f[0] != '/sysboot']
    dests = {f[0] for f in files}

    dirs = set()
    for f in files:
        parts = f[0].split('/')[1:-1]
        for i in range(1, len(parts) + 1):
            dirs.add('/' + '/'.join(parts[:i]))
    if '/base_bscom_open_dir' in zero:
        dirs.add('/bscom')
    # The ri tapes hold files only, so a directory the install leaves empty
    # (`node_data/tmp, systmp, usrtmp, /sys/registry, ...) exists only as a
    # boot-cartridge directory record; take those, except under the names
    # the template turns into links.
    link_names = {'/dev', '/tmp', '/bin'}
    for dpath in boot_dirs:
        if dpath.split('/')[1] == 'install' or any(dpath == l or dpath.startswith(l + '/') for l in link_names):
            continue
        parts = dpath.split('/')[1:]
        for i in range(1, len(parts) + 1):
            dirs.add('/' + '/'.join(parts[:i]))

    links = []
    for line in open(args.links):
        if line.startswith('#') or not line.strip():
            continue
        p, text, src = line.rstrip('\n').split('\t')
        parent = p.rsplit('/', 1)[0] or '/'
        if p.startswith('/install/'):
            continue  # the boot cartridge's install-tool links: of /install/tools only rgy_create goes on
        if (parent == '/' or parent in dirs) and p not in dests and p not in dirs:
            links.append((p, text, src))

    q = shlex.quote
    out = []
    w = out.append
    w('#!/usr/bin/env bash')
    w('# GENERATED by scripts/gen_build_sr10.2_dn2500.py - do not edit; regenerate instead.')
    w('#')
    w('# Builds a native SR10.2 disk for a DN2500 (sau9) from the SR10.2 release:')
    w('#   template   install/templates/apollo/os.v.10.2/%s (%d subcomponents, %d tape files)' % (args.template, len(selected), len(tapefiles)))
    w('#   objects    the selected tape files of the std cartridges, attributes from their tape records')
    w('#   + /sys/types, /install/tools/rgy_create and the soft links in scripts/sr10.2_links.tsv (boot cartridge, see NOTES)')
    for (qq, aa), paths in sorted(ANSWER_SKIPS.items()):
        if answers.get(qq) == aa:
            w('#   %s answers %s=%s: not installed: %s' % (args.template.replace('aa.', 'ov.', 1), qq, aa, ' '.join(paths)))
    for a, b in sorted(RENAMES.items()):
        w('#   emulator workaround: %s is installed as %s (see the generator)' % (a, b))
    w('#')
    w('# usage: build_sr10.2_dn2500.sh [sr10.2 release root] [output image]')
    w('# The release root defaults to the tree scripts/unpack_sr10.2.sh unpacks from tapes/sr10.2/.')
    w('# Writes the image and <image>.sha256.  Set SOURCE_DATE_EPOCH for a reproducible image.')
    w('set -euo pipefail')
    w('SRC="${1:-$("$(dirname "$0")/../../scripts/unpack_sr10.2.sh")}"')
    w('IMG="${2:-$(cd "$(dirname "$0")/.." && pwd)/dn2500_sr10.2.hd}"')
    w('AF="${APOLLOFS:-$("$(dirname "$0")/../../scripts/install_apollofs.sh")}"')
    w('af() { "$AF" -i "$IMG" "$@"; }')
    w('')
    w("# Apollo's 200 MB internal SCSI disk: %s cylinders/heads/sectors (512-byte sectors)," % SCSI_GEOMETRY)
    w("# a geometry MAME's raw .hd loader guesses back; no block headers; dtype 0x700 + 10 MB units.")
    w('rm -f "$IMG" "$IMG.sha256"')
    w('"$AF" -i "$IMG" invol --scsi %s --name DN2500 --node-id 12345 --revision "revision 10.2"' % SCSI_GEOMETRY)
    if sysboot:
        d, src, attrs, typ, size, sc = sysboot[0]
        w('')
        w('# %s' % sc)
        w('af cpboot -a %s "$SRC"/%s' % (attrs, q(src)))
    w('')
    w('# directories (%d)' % len(dirs))
    for dpath in sorted(dirs, key=lambda p: (p.count('/'), p)):
        if dpath in boot_dirs:
            attrs, extra = boot_dirs[dpath]
            w('af mkdir -a %s --dir-defprot %s --file-defprot %s %s' % (attrs, extra[0x40:0xA8], extra[0xA8:0x100], q(dpath)))
        else:
            w('af mkdir %s' % q(dpath))
    w('')
    w('# files (%d)' % len(files))
    last = None
    for d, src, attrs, typ, size, sc in sorted(files, key=lambda f: (f[5], f[0])):
        if sc != last:
            w('# subcomponent %s' % sc)
            last = sc
        w('af copyin -q -a %s "$SRC"/%s %s' % (attrs, q(src), q(d)))
    w('')
    w('# soft links (%d)' % len(links))
    for p, text, src in links:
        w('af crl %s %s   # %s' % (q(p), q(text), src))
    w('')
    w('af check')
    w('')
    w('sum=$(command -v sha256sum || echo "shasum -a 256")')
    w('(cd "$(dirname "$IMG")" && $sum "$(basename "$IMG")" > "$(basename "$IMG").sha256")')
    w('cat "$IMG.sha256"')
    open(args.out, 'w').write('\n'.join(out) + '\n')
    print('%s: %d dirs, %d files, %d links' % (args.out, len(dirs), len(files), len(links)), file=sys.stderr)


if __name__ == '__main__':
    main()
