#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
#
# Contract of scripts/gen-boot-menu.
#
#   gen-boot-menu grub|syslinux < boot-entries.tsv > menu
#
# One table drives both bootloaders, so the BIOS and UEFI menus cannot drift.
# Rows are  id <TAB> title [<TAB> extra kernel parameters]. The first row is
# the default entry. A malformed table fails with EX_DATAERR and no output.

bats_require_minimum_version 1.5.0

readonly EX_USAGE=64
readonly EX_DATAERR=65

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  GEN="$REPO_ROOT/scripts/gen-boot-menu"
  TABLE=$'live\tPanicOS\nram\tPanicOS to RAM\ttoram nopersistence'
}

@test "grub: one menuentry per row, in order, each with kernel and initrd" {
  run "$GEN" grub <<< "$TABLE"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^menuentry ' <<< "$output")" -eq 2 ]
  [ "$(grep '^menuentry ' <<< "$output" | head -1)" = 'menuentry "PanicOS" {' ]
  [ "$(grep -c 'linux.*@KERNEL_LIVE@ @APPEND_LIVE@' <<< "$output")" -eq 2 ]
  [ "$(grep -c 'initrd.*@INITRD_LIVE@' <<< "$output")" -eq 2 ]
}

@test "grub: extra parameters follow the common ones" {
  run "$GEN" grub <<< "$TABLE"
  grep --quiet '@APPEND_LIVE@ toram nopersistence$' <<< "$output"
}

@test "grub: the menu boots unattended after a timeout" {
  run "$GEN" grub <<< "$TABLE"
  grep --quiet --extended-regexp '^set timeout=[1-9][0-9]*$' <<< "$output"
}

@test "grub: output avoids the bare words live-build rewrites for old configs" {
  # binary_grub_cfg replaces these anywhere in the file, even in comments.
  run "$GEN" grub <<< "$TABLE"
  stripped="$(sed 's/@[A-Z_]*@//g' <<< "$output")"
  ! grep --quiet --extended-regexp 'LINUX_LIVE|KERNEL_LIVE|INITRD_LIVE|APPEND_LIVE|MEMTEST|LINUX_INSTALL' <<< "$stripped"
}

@test "syslinux: one label per row, in order, the first one the default" {
  run "$GEN" syslinux <<< "$TABLE"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^label ' <<< "$output")" -eq 2 ]
  [ "$(grep '^label ' <<< "$output" | head -1)" = 'label live' ]
  [ "$(grep -c 'menu default' <<< "$output")" -eq 1 ]
  [ "$(grep -A2 '^label live' <<< "$output" | grep -c 'menu default')" -eq 1 ]
}

@test "syslinux: extra parameters follow the common ones" {
  run "$GEN" syslinux <<< "$TABLE"
  grep --quiet 'append @APPEND_LIVE@ toram nopersistence$' <<< "$output"
}

@test "both menus offer the same titles in the same order" {
  grub_titles="$("$GEN" grub <<< "$TABLE" | sed -n 's/^menuentry "\(.*\)" {$/\1/p')"
  syslinux_titles="$("$GEN" syslinux <<< "$TABLE" | sed -n 's/^\tmenu label //p')"
  [ -n "$grub_titles" ]
  [ "$grub_titles" = "$syslinux_titles" ]
}

@test "comments and blank lines in the table are ignored" {
  run "$GEN" grub <<< $'# menu\n\nlive\tPanicOS'
  [ "$status" -eq 0 ]
  [ "$(grep -c '^menuentry ' <<< "$output")" -eq 1 ]
}

@test "an unknown format is a usage error" {
  run --separate-stderr "$GEN" lilo <<< "$TABLE"
  [ "$status" -eq "$EX_USAGE" ]
  [ -z "$output" ]
}

@test "a row without a title is rejected" {
  run --separate-stderr "$GEN" grub <<< 'live'
  [ "$status" -eq "$EX_DATAERR" ]
  [ -z "$output" ]
  [[ "$stderr" == *"line 1"* ]]
}

@test "a title that would break out of its quotes is rejected" {
  run --separate-stderr "$GEN" grub <<< $'live\tPanic"OS'
  [ "$status" -eq "$EX_DATAERR" ]
  [ -z "$output" ]
}

@test "a duplicate id is rejected" {
  run --separate-stderr "$GEN" syslinux <<< $'live\tA\nlive\tB'
  [ "$status" -eq "$EX_DATAERR" ]
  [[ "$stderr" == *"duplicate"* ]]
}

@test "an empty table is rejected" {
  run --separate-stderr "$GEN" grub <<< '# nothing'
  [ "$status" -eq "$EX_DATAERR" ]
}

@test "the repository's table generates both menus" {
  run "$GEN" grub < "$REPO_ROOT/manifest/boot-entries.tsv"
  [ "$status" -eq 0 ]
  run "$GEN" syslinux < "$REPO_ROOT/manifest/boot-entries.tsv"
  [ "$status" -eq 0 ]
}

@test "BIOS and UEFI menus wait the same time before booting" {
  grub_seconds="$("$GEN" grub <<< "$TABLE" | sed -n 's/^set timeout=//p')"
  # isolinux counts in tenths of a second.
  isolinux_tenths="$(sed -n 's/^timeout //p' "$REPO_ROOT/live/config/bootloaders/isolinux/isolinux.cfg")"
  [ "$isolinux_tenths" -eq $((grub_seconds * 10)) ]
}

@test "syslinux: the menu is titled PanicOS" {
  run "$GEN" syslinux <<< "$TABLE"
  grep --quiet --line-regexp 'menu title PanicOS' <<< "$output"
}

@test "grub: the utilities block follows the entries" {
  run "$GEN" grub <<< "$TABLE"
  [ "$status" -eq 0 ]
  last_entry="$(grep -n '^menuentry ' <<< "$output" | tail -1 | cut -d: -f1)"
  utilities="$(grep -n '^submenu ' <<< "$output" | head -1 | cut -d: -f1)"
  [ "$utilities" -gt "$last_entry" ]
  grep --quiet 'fwsetup' <<< "$output"
}

@test "grub: a malformed table emits nothing, not even the utilities block" {
  run --separate-stderr "$GEN" grub <<< 'broken'
  [ "$status" -eq "$EX_DATAERR" ]
  [ -z "$output" ]
}
