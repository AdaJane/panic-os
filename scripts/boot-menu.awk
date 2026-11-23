# SPDX-License-Identifier: MIT
# boot-menu.awk — turn the boot-entry table into a bootloader menu.
#
# Run through scripts/gen-boot-menu, which sets `format` to "grub" or
# "syslinux".
#
# Reads:  TAB-separated rows  id <TAB> title [<TAB> extra kernel parameters]
#         Blank lines and lines starting with '#' are ignored.
# Emits:  grub:     the head of a grub.cfg: settings and one menuentry per
#                   row. gen-boot-menu appends the utilities block.
#         syslinux: a live.cfg.in, the entry list included by the stock menu
#         Both keep live-build's @...@ placeholders for the kernel, the
#         initrd and the common kernel parameters; live-build fills them in.
# Fails:  exit 65 (EX_DATAERR), naming each bad line on stderr and emitting
#         nothing, if the table is malformed or empty.
#
# Written for POSIX awk.

BEGIN {
	FS = "\t"
	EX_DATAERR = 65
	ID = "^[a-z][a-z0-9-]*$"
	# What a kernel parameter list may contain. Excludes anything that
	# could end a quoted string or a line in either menu format.
	KERNEL_PARAMETERS = "^[A-Za-z0-9_.,=:/ -]*$"
	# A recovery stick must boot unattended. Keep in step with the timeout
	# in live/config/bootloaders/isolinux/isolinux.cfg (tests/unit/boot-menu.bats).
	TIMEOUT_SECONDS = 5
	MENU_TITLE = "PanicOS"
	error_count = 0
	entry_count = 0
}

function reject(reason) {
	printf "boot-entries: line %d: %s\n", NR, reason > "/dev/stderr"
	error_count++
}

{ sub(/\r$/, "") }

/^[ \t]*$/ || /^#/ { next }

NF < 2 || NF > 3 {
	reject("expected 2 or 3 TAB-separated fields, found " NF)
	next
}

$1 !~ ID {
	reject("invalid id '" $1 "'")
	next
}

$2 == "" || $2 ~ /["\\]/ {
	reject("a title must be non-empty and free of quotes and backslashes")
	next
}

$3 !~ KERNEL_PARAMETERS {
	reject("invalid kernel parameters '" $3 "'")
	next
}

$1 in seen {
	reject("duplicate id '" $1 "'")
	next
}

{
	seen[$1] = 1
	entry_count++
	id[entry_count] = $1
	title[entry_count] = $2
	extra[entry_count] = ($3 == "" ? "" : " " $3)
}

function emit_grub(    i) {
	print "# Generated from manifest/boot-entries.tsv by scripts/gen-boot-menu."
	print ""
	print "source /boot/grub/config.cfg"
	print ""
	print "set timeout=" TIMEOUT_SECONDS
	for (i = 1; i <= entry_count; i++) {
		print ""
		print "menuentry \"" title[i] "\" {"
		print "\tlinux\t@KERNEL_LIVE@ @APPEND_LIVE@" extra[i]
		print "\tinitrd\t@INITRD_LIVE@"
		print "}"
	}
	print ""
}

function emit_syslinux(    i) {
	print "# Generated from manifest/boot-entries.tsv by scripts/gen-boot-menu."
	print ""
	print "menu title " MENU_TITLE
	for (i = 1; i <= entry_count; i++) {
		print ""
		print "label " id[i]
		print "\tmenu label " title[i]
		if (i == 1)
			print "\tmenu default"
		print "\tlinux @LINUX@"
		print "\tinitrd @INITRD@"
		print "\tappend @APPEND_LIVE@" extra[i]
	}
}

END {
	if (error_count == 0 && entry_count == 0) {
		print "boot-entries: no entries" > "/dev/stderr"
		error_count++
	}
	if (error_count > 0)
		exit EX_DATAERR
	if (format == "grub")
		emit_grub()
	else
		emit_syslinux()
}
