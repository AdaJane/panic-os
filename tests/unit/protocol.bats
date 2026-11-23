#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
#
# Facts that have to be written in two places because one of them is not a
# shell file. These tests fail if the copies drift.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  INCLUDES="$REPO_ROOT/live/config/includes.chroot"
  # shellcheck source=live/config/includes.chroot/usr/lib/panicos/constants.sh
  source "$INCLUDES/usr/lib/panicos/constants.sh"
}

@test "the self-test unit is gated on the credential the harness passes" {
  grep --quiet --line-regexp --fixed-strings \
    "ConditionCredential=$PANICOS_SELFTEST_CREDENTIAL" \
    "$INCLUDES/etc/systemd/system/panicos-selftest.service"
}
