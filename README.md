# Apollo Domain/OS disk images

Bootable Apollo Domain/OS disk images, one directory per SAU (the
processor/board family a kernel image is built for), with the scripts
that build each one from the original release files.

| SAU  | Machines                | Image                    | Release | Size              |
| ---- | ----------------------- | ------------------------ | ------- | ----------------- |
| sau2 | DN300, DN320, DN330     | `sau2/dn300_sr10.2.awd`  | SR10.2  | 66,464,640 bytes  |
| sau7 | DN3500, DN4500, DN5500  | `sau7/dn3500_sr10.2.awd` | SR10.2  | 348,701,760 bytes |
| sau9 | DN2500                  | `sau9/dn2500_sr10.2.hd`  | SR10.2  | 206,438,400 bytes |

Each image directory holds `scripts/`, the commands that build its
image.  The images are not in the repository (`.gitignore` excludes
`*.awd`, `*.hd` and their `.sha256` checksums): build them with the
scripts, or download the finished images from the repository's GitHub
releases.

The images are in two formats because MAME's machines use different
disk devices.  The DN300's disk (`.awd`, "Apollo Winchester Disk", MAME's
`ansi_disk_device`) and the DN3500's (the OMTI 8621's, also `.awd`) keep
Apollo's block headers, so each block is 1056 bytes: 32 bytes of header
and 1024 of data.  The DN2500's disk is plain SCSI with no headers, so
its image is a raw `.hd` of 512-byte sectors, the format of MAME's
generic hard disk loader.

## The SR10.2 release files

Both images are built from the SR10.2 release cartridges on bitsavers
(`bits/Apollo/Apollo_JRJ/SR10.2/`), which go in `tapes/sr10.2/`.
`scripts/unpack_sr10.2.sh` checks them against the checksums in the
script and unpacks them into a cache with
[readct](https://github.com/domainos-archeology/readct):

| In `cache/sr10.2/` | What                                                        |
| ------------------ | ----------------------------------------------------------- |
| `tapes/`           | the five cartridges, gunzipped (`.ct`)                      |
| `release/`         | the boot and three standard cartridges extracted into one tree: the release root the scripts read |
| `incr2/`           | the INCR2 patch cartridge (`suid_exec` for a running node's `/etc`), extracted on its own; not on either volume |
| `manifest.tsv`     | `apollofs ctindex` of the four base cartridges, for regenerating the build scripts |

`tapes/` and `cache/` are at the top of the repository and ignored by
git; `SR10_2_TAPES` and `DISK_IMAGES_CACHE` put them elsewhere.
Everything in the cache comes from the tapes and can be deleted.  Each
step is skipped when its output is already there, so the build and
first-boot scripts call it whenever they aren't given a release root,
and after the first run it only prints the root.  readct runs with
`go run` at a pinned commit, or set `READCT` to a readct binary.

The scripts' other tool,
[apollofs](https://github.com/project-phoebus/apollofs), is built by
`scripts/install_apollofs.sh` at the commit pinned there, into
`cache/bin/` the first time it is needed; set `APOLLOFS` to use another
apollofs binary.  Both tools need Go.

### Downloading the cartridges

The scripts don't download anything.  Before running any of them,
download these five files from
<https://bitsavers.org/bits/Apollo/Apollo_JRJ/SR10.2/> and put them,
still gzipped, in `tapes/sr10.2/`:

| File | SHA-256 |
| ---- | ------- |
| `017286-001.CRTG_STD_SFW_BOOT_1-REV.00-SYSTEM_RELEASE_VER_SR10.2-RAI.ct.gz` | `e5354f39a152efb90e136b42291cc6a5f7655b07835959867b81359bfffbd659` |
| `017287-001.CRTG_STD_SFW_1-REV.00-SYSTEM_RELEASE_VER_SR10.2-RAI.ct.gz` | `e51daf7f00be2e60f985dda274490e332987bf47720cbff06316f439c70dc1cc` |
| `017287-002.CRTG_STD_SFW_2-REV.00-SYSTEM_RELEASE_VER_SR10.2-RAI.ct.gz` | `9ba43e2927dcff40193c5f088e940e58501b252fe4a7d29eb1971dacf89dabd0` |
| `017287-003.CRTG_STD_SFW_3-REV.00-SYSTEM_RELEASE_VER_SR10.2-RAI.ct.gz` | `1304b50c2e55878979b2981b205d9f2eb57c2d35d2ff3c1c8f877e6aaa40cda7` |
| `018777-001.CRTG_OS_INCR2_1.SR10.2-INCRA_2.ct.gz` | `644cce656f0d7abd9f4b9428286175aeace4d63d9199388b73096080c4623ef4` |

`unpack_sr10.2.sh` stops and lists the URLs of any that are missing.
It checks each file against its checksum, so a file that has changed
since these checksums were taken stops it with a checksum mismatch
rather than building a different volume.

## sau2: SR10.2 for the DN300

A native SR10.2 volume for a DN300 with the largest disk MAME's DN300
model emulates (Priam 7050, drive type 0x105, 62,940 blocks).  It boots
the original SR10.2 kernel through `/etc/rc` to the Display Manager's
login.  Log in as `root` with password `-apollo-` (every reserved
account the registry was created with has that password).

It is built in two stages:

1. `scripts/build_sr10.2_dn300.sh [release root] [output image]` creates
   the volume with apollofs: the label, sysboot, and every object of
   the SR10.2 "aegis small" install template
   (`install/templates/apollo/os.v.10.2/aa.aegis_small`), with the
   attributes recorded on the release tapes, plus `/sys/types`, the
   boot cartridge's links (`scripts/sr10.2_links.tsv`) and
   `/install/tools/rgy_create`, and writes the image (by default
   `sau2/dn300_sr10.2.awd`) and its `.sha256`.  It takes about 12
   seconds.  The script
   is generated by `scripts/gen_build_sr10.2_dn300.py` from an
   `apollofs ctindex` manifest of the four SR10.2 cartridges; regenerate
   it rather than editing it.
2. `scripts/first_boot_sr10.2_dn300.sh <image>` boots the original
   SR10.2 kernel on the new volume under MAME and types, at the Phase II
   prompt, the commands that create the node's registry (`rgy_create`),
   its location-broker database and the daemon marker files, then shuts
   down cleanly.  The SR10.2 tapes ship no registry: it is built on a
   running node.  The image is modified in place and is the finished
   volume afterwards.  It takes about 8 minutes.

What the scripts need:

- Go, for apollofs and readct (see above), or `APOLLOFS` and `READCT`;
- the SR10.2 release files: by default the cache
  `scripts/unpack_sr10.2.sh` fills from `tapes/sr10.2/` (which needs Go,
  or `READCT`), or a release root passed to the build script / set as
  `SR102` for the first boot;
- for the first boot: MAME with the DN300 machine, and the kernel
  repository's boot harness (`domain_os/tools/mame_boot_direct.py`),
  located through `DOMAIN_OS`; the SR10.2 kernel comes from the release
  root and its link map through `MAP`.

The first boot's defaults for `DOMAIN_OS` and `MAP` assume the directory
layout of the project's checkout; set the variables to use others.

To regenerate the build script after changing the generator:

    sau2/scripts/gen_build_sr10.2_dn300.py \
        --manifest cache/sr10.2/manifest.tsv \
        --install-root cache/sr10.2/release \
        --links sau2/scripts/sr10.2_links.tsv \
        --out sau2/scripts/build_sr10.2_dn300.sh

Not on the volume: the X server (`create_xapollo=no` in the template's
answers).  `/sys/peb2_microcode` is installed as
`/sys/peb2_microcode.do_not_use`: MAME answers the PEB2 floating-point
board's probe but doesn't emulate its writable control store, so loading
the microcode stops the boot with status 00240009 ("wcs verify failed").
Rename it back for real hardware with a PEB2.

## sau7: SR10.2 for the DN3500, DN4500 and DN5500

A native SR10.2 volume holding as much of the release as an install can
put on a node, so that it can be the netboot partner of a diskless node
of any SAU.  Log in as `root` with password `-apollo-`.

The disk is the Maxtor XT-4380E (380 MB unformatted) on the OMTI 8621
ESDI controller, as MAME's DN3500 has it: 1223 cylinders x 15 heads x 18
blocks of 1056 bytes (a 32-byte header and 1024 bytes of data, like the
DN300's), 348,701,760 bytes, the size MAME gives a new disk.  The PV
label is the one an SR10 invol writes for that disk: drive type 0x504,
a 329,400-block volume, and the last three cylinders reserved for the
diagnostic area and the badspot list (apollofs's NOTES.md, "ESDI
volumes").

What is on the volume:

- every object of the SR10.2 `aa.large` install template, the union of
  all the others: the Aegis, BSD4.3 and SysV.3 environments, X11, the
  examples, systest, and every SAU's `/sauN` (sau2 to sau9 and sau12),
  with the attributes recorded on the release tapes, plus `/sys/types`,
  `/install/tools/rgy_create` and the links the install makes
  (`scripts/sr10.2_links.tsv`: those of the sau2 volume and the
  environments' links, taken from an installed SR10.3 volume where the
  SR10.2 release database has the same link text).  About 130 MB of the
  volume is used.
- netman, the diskless node boot server (`/sys/net/netman`), enabled:
  the four commented-out lines that start it in
  `` `node_data/etc/rc.user `` are uncommented, as the SR10.2 release
  notes tell a partner to do.  The build patches a copy of the release
  file, checking each byte it changes.  `/sys/net/diskless_list` is as
  the release ships it, with no nodes in it.
- not the X server marker (`create_xapollo=no`, as on the other
  volumes); `/sys/peb2_microcode` under its own name (no PEB).

It is built in two stages, like the others:

1. `scripts/build_sr10.2_dn3500.sh [release root] [output image]`
   creates the volume with apollofs (`invol -t 504`) and writes the
   image and its `.sha256`; it takes about 5 minutes.  The script is
   generated by `scripts/gen_build_sr10.2_dn3500.py`; regenerate it
   rather than editing it:

       sau7/scripts/gen_build_sr10.2_dn3500.py \
           --manifest cache/sr10.2/manifest.tsv \
           --install-root cache/sr10.2/release \
           --links sau7/scripts/sr10.2_links.tsv \
           --out sau7/scripts/build_sr10.2_dn3500.sh

2. `scripts/first_boot_sr10.2_dn3500.sh <image>` boots it under MAME's
   DN3500 (the kernel repository's `domain_os/tools/mame_boot_dn3500.py`,
   located through `DOMAIN_OS`; the PROM in Service mode, `ex domain_os`
   at its `>` prompt) and creates the registry, location-broker database
   and daemon markers as on the other volumes, then shuts down.  The
   harness sees only the PROM's console output, so the script types each
   line when the CPU goes idle and checks the result on the volume
   afterwards with apollofs.  It takes about a minute.

Under MAME's DN3500, in Service mode, `ex domain_os` at the PROM's `>`
prompt loads the SR10.2 kernel and `go` at the Phase II `)` prompt
starts Init: `/etc/rc` starts llbd, glbd and rgyd, `/etc/rc.user`
netman, and the Display Manager comes up.

## sau9: SR10.2 for the DN2500

A native SR10.2 volume for a DN2500 (Series 2500) on its internal SCSI
disk.  It carries the same objects as the sau2 DN300 volume: the SR10.2
"aegis small" install template holds every SAU's `/sauN`, so `/sau9` has
the SAU9 kernel (`/sau9/domain_os`) and its standalone utilities.

| Image                | Disk                            | Size              |
| -------------------- | ------------------------------- | ----------------- |
| `dn2500_sr10.2.hd`   | SCSI, 400 cyl x 16 heads x 63   | 206,438,400 bytes |

The disk is Apollo's 200 MB internal Winchester, the one a typical
Series 2500 was configured with (the factory offered 100 MB and 200 MB
internal disks).  Its geometry, 400 x 16 x 63 512-byte sectors, is one
MAME's raw `.hd` loader guesses back from the image's size, so the
emulated disk reports it in READ CAPACITY and its mode pages.

A SCSI disk keeps no Apollo block headers: the image is a flat array of
1024-byte blocks, block N at byte N x 1024 (LBAs 2N and 2N+1).  The PV
label is the one the SR10.2 invol writes for such a disk: drive type
0x713 (0x700 plus the capacity in 10 MB units), 63 sectors per track,
16 heads, one sector per block, 198,574 blocks in the volume, and the
badspot list and diagnostic cylinders past its end (`addr_end` 201,599).
sysboot is in PV blocks 2..11, which the label names at 0xA4 (its first
block) and 0xFA (its 10 blocks): the DN2500's PROM loads it from there.

It is built by `scripts/build_sr10.2_dn2500.sh [release root] [output
image]`, which writes the image and its `.sha256`.  The script is
generated by `scripts/gen_build_sr10.2_dn2500.py` from an `apollofs
ctindex` manifest of the four SR10.2 cartridges and
`scripts/sr10.2_links.tsv`; regenerate it rather than editing it:

    sau9/scripts/gen_build_sr10.2_dn2500.py \
        --manifest cache/sr10.2/manifest.tsv \
        --install-root cache/sr10.2/release \
        --links sau9/scripts/sr10.2_links.tsv \
        --out sau9/scripts/build_sr10.2_dn2500.sh

It needs apollofs with SCSI support (`invol --scsi`; the commit
`scripts/install_apollofs.sh` pins has it) and the SR10.2 release
files, by default from the cache (see above).
`SOURCE_DATE_EPOCH`, if set, is the time apollofs stamps, which makes
the image reproducible; the project builds it with 675734400
(1991-06-01 00:00 UTC), since the Domain/OS clock ends in 2015.

Unlike the DN300 volume, `/sys/peb2_microcode` keeps its name: the
DN2500 has no PEB.

Like the DN300 volume, it is built in two stages: the build script above,
then `scripts/first_boot_sr10.2_dn2500.sh <image>`, which boots it under
MAME's DN2500 model and creates the node's registry, location-broker
database and daemon markers the same way (see the sau2 section), then
shuts down cleanly.  The image is then the finished volume.  Log in as
`root` with password `-apollo-`.

Under the DN2500 model, with 16 MB of RAM in one bank, the MD9 PROM
boots it.  With a monitor and the keyboard as console (a Return at power
on), `boot` at the PROM's prompt loads the SR10.2 kernel, `go` at the
Phase II `)` prompt starts Init, and the Display Manager comes up; with
a serial console the node runs as a server instead.  The calendar must
be before 2015, where the Domain/OS clock ends, and no more than a
minute behind the label's last valid time, which the first boot's
shutdown left at 1991-06-01 12:08 (the first boot runs with the calendar
at 1991-06-01 12:00).

## Releases

`scripts/release.sh <tag>` builds every image, runs its first boot,
compresses it with `xz -9e`, and uploads the compressed images and
their `.sha256` checksums as assets of the GitHub release `<tag>`:

    git tag v1 && git push origin v1
    gh release create v1 --title v1 --notes '...'
    scripts/release.sh v1

The working tree must be clean and checked out at the tag, and the
release must already exist; all of that is checked before anything is
built.  The images are built in `dist/<tag>/` (ignored by git) with
`SOURCE_DATE_EPOCH` 675734400 unless it is set, along with each stage's
log.  Assets already on the release with the same names are replaced.
The build stage is reproducible but the first boot is not (the node
writes its registry and the label's times as it runs), so the checksums
on a release identify those images, not what a rebuild will produce.
`NO_UPLOAD=1` builds the images without the checks and without
uploading.

To use a release's image, check and decompress it:

    shasum -a 256 -c dn300_sr10.2.awd.xz.sha256
    xz -d dn300_sr10.2.awd.xz

The checksums cover the `.xz` files as downloaded.  The images compress
well because most of each volume is free space: the 66 MB DN300 image
to about 10 MB, the 349 MB DN3500 image to about 22 MB, the 206 MB
DN2500 image to about 9 MB.
