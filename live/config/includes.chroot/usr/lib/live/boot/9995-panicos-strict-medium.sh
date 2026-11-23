#!/bin/sh
# SPDX-License-Identifier: MIT
#
# PanicOS: look for the live medium only where the kernel command line says
# it is. Sourced by live-boot in the initramfs after 9990-misc-helpers.sh,
# whose find_livefs this replaces.
#
# Stock find_livefs falls back to scanning every disk in the machine and
# mounting each filesystem it finds, to see whether it holds a live image.
# Mounting an ext4 or NTFS volume that was not shut down cleanly replays its
# journal, even read-only: a write to a client disk before the operator has
# seen a prompt. It happens whenever the stick is not found first, which is
# the normal case for USB SSDs and other sticks that present as fixed disks.
#
# So: no scan. live-media= must name a block device (PanicOS boots with
# live-media=/dev/disk/by-label/<ISO label>, see live/auto/config), and that
# device is the only one ever mounted here.
#
# Consequence: booting the ISO as a file from another filesystem (findiso=,
# fromiso=, Ventoy) is not supported.

find_livefs ()
{
	# ${1} is live-boot's count of seconds waited so far; live-boot calls
	# this once a second until it succeeds or the boot times out.
	case "${LIVE_MEDIA}" in
		/dev/*)
			;;
		*)
			echo "PanicOS: live-media= must name a device; refusing to scan disks for the live medium." > /dev/console
			return 1
			;;
	esac

	# Not there yet: USB devices can take a few seconds to appear.
	[ -b "${LIVE_MEDIA}" ] || return 1

	check_dev "null" "${LIVE_MEDIA}"
}
