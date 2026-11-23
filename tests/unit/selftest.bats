#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
#
# Contract of panicos-selftest.
#
#   panicos-selftest [MANIFEST]
#
#   exit 0, no output   every binary is on PATH and every smoke command passed
#   exit 1              at least one tool failed; one line per failure on stderr
#   exit 65             the manifest itself is malformed

bats_require_minimum_version 1.5.0

readonly EX_TOOL_FAILED=1
readonly EX_DATAERR=65
readonly ABSENT_BINARY=panicos-no-such-binary

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SELFTEST="$REPO_ROOT/live/config/includes.chroot/usr/bin/panicos-selftest"
  MANIFEST="$BATS_TEST_TMPDIR/tools.tsv"
}

manifest() { printf '%s\n' "$@" > "$MANIFEST"; }

@test "selftest: silent success when every tool is present" {
  manifest $'coreutils\tls' $'coreutils\ttrue\ttrue'
  run --separate-stderr "$SELFTEST" "$MANIFEST"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "selftest: a missing binary fails and is named on stderr" {
  manifest $'ghostpkg\t'"$ABSENT_BINARY"
  run --separate-stderr "$SELFTEST" "$MANIFEST"
  [ "$status" -eq "$EX_TOOL_FAILED" ]
  [ -z "$output" ]
  [[ "$stderr" == *"ghostpkg"* ]]
  [[ "$stderr" == *"$ABSENT_BINARY"* ]]
}

@test "selftest: a failing smoke command fails and is quoted on stderr" {
  manifest $'coreutils\tfalse\tfalse'
  run --separate-stderr "$SELFTEST" "$MANIFEST"
  [ "$status" -eq "$EX_TOOL_FAILED" ]
  [[ "$stderr" == *"smoke"* ]]
}

@test "selftest: smoke command output never reaches stdout or stderr on success" {
  manifest $'coreutils\techo\techo noise; echo more-noise >&2'
  run --separate-stderr "$SELFTEST" "$MANIFEST"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "selftest: every failure is reported, one per line" {
  manifest $'pkg-a\t'"$ABSENT_BINARY"'-a' $'coreutils\tls' $'pkg-b\t'"$ABSENT_BINARY"'-b'
  run --separate-stderr "$SELFTEST" "$MANIFEST"
  [ "$status" -eq "$EX_TOOL_FAILED" ]
  [ "${#stderr_lines[@]}" -eq 2 ]
}

@test "selftest: a smoke command that reads stdin cannot swallow later rows" {
  manifest $'coreutils\tcat\tcat' $'ghostpkg\t'"$ABSENT_BINARY"
  run --separate-stderr "$SELFTEST" "$MANIFEST"
  [ "$status" -eq "$EX_TOOL_FAILED" ]
  [[ "$stderr" == *"ghostpkg"* ]]
}

@test "selftest: a malformed manifest is a data error, not a tool failure" {
  manifest 'not-a-valid-row'
  run --separate-stderr "$SELFTEST" "$MANIFEST"
  [ "$status" -eq "$EX_DATAERR" ]
}

@test "selftest: a missing manifest file fails" {
  run --separate-stderr "$SELFTEST" "$BATS_TEST_TMPDIR/absent.tsv"
  [ "$status" -ne 0 ]
}
