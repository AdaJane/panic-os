#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
#
# Contract of the tool manifest parser and the package-list generator.
#
#   manifest.awk      TSV on stdin -> canonical "package<TAB>binary<TAB>smoke" rows
#   gen-package-list  TSV on stdin -> sorted, unique package names
#
# Malformed input is a bug in the manifest: both fail with EX_DATAERR, name the
# offending line on stderr, and emit nothing on stdout.

bats_require_minimum_version 1.5.0

readonly EX_DATAERR=65

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  MANIFEST_AWK="$REPO_ROOT/live/config/includes.chroot/usr/lib/panicos/manifest.awk"
  GEN_PACKAGE_LIST="$REPO_ROOT/scripts/gen-package-list"
}

parse() { awk -f "$MANIFEST_AWK"; }

@test "manifest: a two-field row gains an empty smoke column" {
  run parse <<< $'testdisk\tphotorec'
  [ "$status" -eq 0 ]
  [ "$output" = $'testdisk\tphotorec\t' ]
}

@test "manifest: a three-field row passes through unchanged" {
  run parse <<< $'rustc\trustc\trustc --version'
  [ "$status" -eq 0 ]
  [ "$output" = $'rustc\trustc\trustc --version' ]
}

@test "manifest: comments and blank lines are ignored" {
  run parse <<< $'# recovery\n\ntestdisk\ttestdisk\n   \n# end'
  [ "$status" -eq 0 ]
  [ "$output" = $'testdisk\ttestdisk\t' ]
}

@test "manifest: CRLF line endings are accepted" {
  run parse <<< $'testdisk\ttestdisk\r'
  [ "$status" -eq 0 ]
  [ "$output" = $'testdisk\ttestdisk\t' ]
}

@test "manifest: one package may provide several binaries" {
  run parse <<< $'testdisk\ttestdisk\ntestdisk\tphotorec'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "manifest: a row with one field is rejected with its line number" {
  run --separate-stderr parse <<< $'testdisk\ttestdisk\ngparted'
  [ "$status" -eq "$EX_DATAERR" ]
  [ -z "$output" ]
  [[ "$stderr" == *"line 2"* ]]
}

@test "manifest: a row with four fields is rejected" {
  run --separate-stderr parse <<< $'a1\tb\tc\td'
  [ "$status" -eq "$EX_DATAERR" ]
  [ -z "$output" ]
}

@test "manifest: space-separated columns are rejected, not guessed at" {
  run --separate-stderr parse <<< 'testdisk photorec'
  [ "$status" -eq "$EX_DATAERR" ]
  [ -z "$output" ]
}

@test "manifest: an invalid package name is rejected" {
  run --separate-stderr parse <<< $'Test_Disk\ttestdisk'
  [ "$status" -eq "$EX_DATAERR" ]
  [[ "$stderr" == *"package"* ]]
}

@test "manifest: an empty binary name is rejected" {
  run --separate-stderr parse <<< $'testdisk\t\ttrue'
  [ "$status" -eq "$EX_DATAERR" ]
  [[ "$stderr" == *"binary"* ]]
}

@test "manifest: a duplicate package/binary pair is rejected" {
  run --separate-stderr parse <<< $'testdisk\ttestdisk\ntestdisk\ttestdisk'
  [ "$status" -eq "$EX_DATAERR" ]
  [[ "$stderr" == *"line 2"* ]]
  [[ "$stderr" == *"duplicate"* ]]
}

@test "manifest: every bad line is reported, not just the first" {
  run --separate-stderr parse <<< $'one\nok\tok\ntwo'
  [ "$status" -eq "$EX_DATAERR" ]
  [[ "$stderr" == *"line 1"* ]]
  [[ "$stderr" == *"line 3"* ]]
}

@test "manifest: a manifest with no entries is rejected" {
  run --separate-stderr parse <<< $'# nothing here\n'
  [ "$status" -eq "$EX_DATAERR" ]
  [[ "$stderr" == *"no entries"* ]]
}

@test "gen-package-list: emits each package once, sorted" {
  run "$GEN_PACKAGE_LIST" <<< $'testdisk\tphotorec\ngddrescue\tddrescue\ntestdisk\ttestdisk'
  [ "$status" -eq 0 ]
  [ "$output" = $'gddrescue\ntestdisk' ]
}

@test "gen-package-list: a malformed manifest fails and emits no packages" {
  run --separate-stderr "$GEN_PACKAGE_LIST" <<< $'testdisk\ttestdisk\nbroken'
  [ "$status" -eq "$EX_DATAERR" ]
  [ -z "$output" ]
}

@test "the repository manifest is valid" {
  run "$GEN_PACKAGE_LIST" < "$REPO_ROOT/manifest/tools.tsv"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}
