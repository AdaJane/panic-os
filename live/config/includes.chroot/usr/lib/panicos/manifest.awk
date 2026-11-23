# SPDX-License-Identifier: MIT
# manifest.awk — validate the PanicOS tool manifest and emit canonical rows.
#
# The one parser for manifest/tools.tsv. The build (scripts/gen-package-list)
# and the image (panicos-selftest) both read the manifest through it, so they
# cannot disagree about what a row means.
#
# Reads:  TAB-separated rows  package <TAB> binary [<TAB> smoke-command]
#         Blank lines and lines starting with '#' are ignored. A trailing CR
#         is ignored.
# Emits:  one row per entry, always three fields:
#           package <TAB> binary <TAB> smoke-command-or-empty
# Fails:  exit 65 (EX_DATAERR) if any row is malformed or there are no rows.
#         Every bad line is reported on stderr and nothing is emitted, so a
#         consumer never acts on half a manifest.
#
# Written for POSIX awk: the image has mawk, not gawk.

BEGIN {
	FS = "\t"
	OFS = "\t"
	EX_DATAERR = 65
	PACKAGE_NAME = "^[a-z0-9][a-z0-9+.-]+$"   # Debian policy 5.6.1
	BINARY_NAME = "^[A-Za-z0-9_.+-]+$"
	error_count = 0
	row_count = 0
}

function reject(reason) {
	printf "manifest: line %d: %s\n", NR, reason > "/dev/stderr"
	error_count++
}

{ sub(/\r$/, "") }

/^[ \t]*$/ || /^#/ { next }

NF < 2 || NF > 3 {
	reject("expected 2 or 3 TAB-separated fields, found " NF)
	next
}

$1 !~ PACKAGE_NAME {
	reject("invalid package name '" $1 "'")
	next
}

$2 !~ BINARY_NAME {
	reject("invalid binary name '" $2 "'")
	next
}

($1, $2) in seen {
	reject("duplicate entry for package '" $1 "', binary '" $2 "'")
	next
}

{
	seen[$1, $2] = 1
	rows[++row_count] = $1 OFS $2 OFS $3
}

END {
	if (error_count == 0 && row_count == 0) {
		print "manifest: no entries" > "/dev/stderr"
		error_count++
	}
	if (error_count > 0)
		exit EX_DATAERR
	for (i = 1; i <= row_count; i++)
		print rows[i]
}
