# PanicOS

A USB-bootable live system for data recovery, based on Debian 13 (trixie).

One amd64 image boots under UEFI (Secure Boot included) and legacy BIOS, keeps
its state on the stick, and carries the usual recovery tools together with a
small development toolchain. It is deliberately plain: a minimal XFCE desktop,
no installer, no theming.

- **Recovery:** GParted, TestDisk, PhotoRec, ddrescue, partclone, sleuthkit,
  foremost, smartmontools, and tools for NTFS, exFAT, Btrfs, XFS, F2FS, HFS+,
  APFS, LVM, RAID, LUKS and BitLocker.
- **Development:** GCC, Rust, Python, git, gdb.
- **Network:** NetworkManager, current Firefox, ssh, rsync, sshfs, CIFS, NFS.
- **Claude Code:** not included, but offered on first startup. See
  [Claude Code](#claude-code).

The full list is [`manifest/tools.tsv`](manifest/tools.tsv).

## Status and warranty

PanicOS is tested in virtual machines, as described under [Testing](#testing).
**It has not yet been verified on physical hardware.** Treat it accordingly.

It comes with **no warranty of any kind**. This is a tool you point at disks
that hold the only copy of someone's data. It is built to leave those disks
alone until you act, and that is tested, but you are responsible for what
happens to them. Work on an image of a failing disk, not on the disk.

PanicOS is an independent project. It is based on Debian and is not affiliated
with or endorsed by the Debian project, Mozilla or Anthropic.

## What it promises

1. **It leaves the machine's disks alone.** Booting mounts nothing, enables no
   swap, and assembles no RAID array or LVM volume on the machine's own
   disks. The first two are proven by checksumming a simulated client disk
   before and after a boot.
2. **Every bundled tool works.** One manifest lists them, and the image tests
   itself against it.
3. **It is loud about lost state.** A stick without a working persistence
   volume says so at login.

Stock Debian live images do not make the first promise: while looking for
their boot medium they mount every filesystem they find, which replays the
journal of one that was not shut down cleanly. PanicOS looks for its medium by
volume label only.

## Get an image

Either download one from the repository's Releases page and check it:

```sh
sha256sum --check panicos-*.iso.sha256
```

or build it. Released images are built by CI, which does **not** boot them;
see [Testing](#testing).

## Build

The host needs Docker and `make`, nothing else. The build runs in a privileged
container, because live-build has to mount filesystems in its chroot.

```sh
make iso      # out/panicos-<date>-<commit>-amd64.iso, .sha256, .packages
```

The build downloads from Debian, from Mozilla's apt archive (Firefox) and from
Anthropic's (only to confirm Claude Code can be installed later).

## Testing

```sh
make lint         # shellcheck
make test-unit    # bats: parsers, generators, the rules that guard disk writes
make test-vm      # boots the ISO in QEMU; needs KVM
make test         # all three
```

`make test-vm` boots the ISO as a USB stick, through the real bootloaders,
under BIOS, UEFI and UEFI with Secure Boot enforced:

| Test               | What it proves                                                        |
|--------------------|-----------------------------------------------------------------------|
| `boot-test`        | The image boots, the desktop starts, every manifest tool passes       |
| `persistence-test` | A change made on one boot is there on the next; what the flash and persistence tools refuse |
| `safety-test`      | A disk with an unclean filesystem, swap and another system's persistence volume is bit-for-bit unchanged after a boot |

CI runs lint, the unit tests and the build. It does not run the VM tests.

## Write it to a stick

```sh
make flash DEVICE=/dev/sdX              # encrypted persistence (default)
make flash DEVICE=/dev/sdX ENCRYPT=no   # unencrypted
make persist DEVICE=/dev/sdX            # stick already written by another tool
```

`make flash` **erases the stick**. It verifies the ISO against its checksum,
refuses anything that is not a whole, removable, unmounted disk, shows what it
is about to erase, and asks you to retype the device name. It then writes the
image and adds the persistence volume, asking for a passphrase.

Any other image writer works too, but leaves no persistence volume;
`make persist` adds one. If your desktop auto-mounts the stick as soon as the
image is written, the persistence step refuses it as "in use": unmount it and
run `make persist`.

## Using the stick

The boot menu waits five seconds, then starts the first entry.

| Entry                          | Use it when                                                    |
|--------------------------------|----------------------------------------------------------------|
| PanicOS                        | Normally. State is kept on the stick.                          |
| PanicOS to RAM, no persistence | You need the USB port, or want a session that leaves no trace. |
| PanicOS, text console only     | The graphical desktop will not start.                          |

You are logged in as `panic`, with passwordless `sudo`. With an encrypted
persistence volume, the passphrase is asked for early in the boot.

- **Network:** `nmtui`.
- **Status:** `panicos-status` shows the release and whether state is kept.
- **Self-test:** `panicos-selftest` is silent if every tool works.
- **Updates:** `sudo apt update && sudo apt upgrade` on a persistent stick.

### The machine's disks

Nothing is mounted until you mount it. To look at a disk without changing it,
make it read-only first, then mount without journal replay:

```sh
sudo blockdev --setro /dev/sdX
sudo mount -o ro,noload /dev/sdX1 /mnt        # ext3/ext4
```

RAID and LVM are deliberately not started for you:

```sh
sudo mdadm --assemble --readonly /dev/md0 /dev/sdX1 /dev/sdY1
sudo vgchange --activate y --readonly VG
```

### Claude Code

Claude Code is Anthropic's proprietary software, so PanicOS does not ship it.
On the first desktop login of a persistent stick, PanicOS offers to download
it from Anthropic's own package archive (about 135 MB). Say no and it does not
ask again; either way you can run this at any time:

```sh
panicos-install-claude
```

You use it with your own Anthropic account, under Anthropic's terms. `claude`
prints a sign-in link, which you can open in Firefox. Persistence keeps both
the install and the login.

## Changing what is in the image

| To change                        | Edit                                                |
|----------------------------------|-----------------------------------------------------|
| A bundled tool                   | `manifest/tools.tsv`: package, binary, optional smoke command. The package list and the self-test both come from it. |
| A package with no binary         | `live/config/package-lists/base.list.chroot`        |
| The boot menu                    | `manifest/boot-entries.tsv`: both bootloaders' menus come from it |
| Build options, kernel parameters | `live/auto/config`                                  |
| Files in the image               | `live/config/includes.chroot/`                      |
| A third-party apt archive        | `live/config/archives/` and its key in `live/keyrings/` |

Recommended packages are off to keep the image small, so a dependency that is
only "recommended" has to be listed explicitly.

## Layout

```
Makefile                       entry points
build/Dockerfile               pinned build and test container
manifest/                      tools.tsv, boot-entries.tsv: the sources of truth
scripts/                       build-iso and the two generators
live/auto/config               the one live-build configuration
live/config/                   package lists, apt archives, hooks, image overlay
  includes.chroot/usr/bin/     panicos-flash, -persist, -selftest, -status, ...
  includes.chroot/usr/lib/panicos/
                               constants.sh, device.jq (write-safety rules), ...
live/keyrings/                 signing keys of the third-party apt archives
tests/unit/                    bats: parsers, generators, device-safety rules
tests/vm/                      QEMU: boot, persistence, safety
```

## Known gaps

- **Not yet verified on physical hardware**, as said above.
- **Encrypted persistence is not boot-tested automatically.** The tests check
  that the encrypted volume is created and opens with the passphrase as
  typed, but unlocking it at boot needs a keyboard.
- **Flashing a real stick is not tested automatically**, only its refusals.
- **RAID and LVM safety is configured but not yet VM-tested.** Automatic
  assembly and activation are switched off, and the build checks that the
  settings took; no test yet boots against a disk carrying an array or a
  volume group.
- **The first-startup Claude Code offer is not tested automatically.** Its
  decision logic and the installer are; the prompt itself is not.
- **A persistence volume cannot be added from the running stick**, only from
  the machine that built the image.
- **Booting the ISO as a file** (Ventoy, `findiso=`) is not supported: the
  image looks for its medium by volume label alone, so that it never has to
  search the machine's disks.
- **memtest86+** is in the menu but is not signed, so it will not start with
  Secure Boot on.
- No ZFS and no Clonezilla: left out for size.

## Licence

The code in this repository is under the [MIT licence](LICENSE), copyright
The PanicOS contributors. Two small files adapted from Debian's live-build are
under the [GPL, version 3 or later](LICENSES/GPL-3.0-or-later.txt), as that
project is: `scripts/grub-utilities.cfg` and
`live/config/bootloaders/isolinux/isolinux.cfg`. Every file names its licence
in an `SPDX-License-Identifier` line.

An image built from it is something else: a collection of Debian packages,
each under its own licence, described in `/usr/share/doc/*/copyright` on the
image. Most are free software. Some are not: the firmware from Debian's
`non-free-firmware` section and `hfsprogs` from `non-free`. All may be
redistributed.

- The `.packages` file beside each ISO lists every package and its exact
  version. Source for each is available from Debian, permanently at
  <https://snapshot.debian.org>.
- Firefox is Mozilla's own unmodified build, from Mozilla's apt archive.
- Claude Code is not in the image.
- `live/keyrings/` holds the public signing keys of Anthropic's and Mozilla's
  archives. They belong to their owners.
