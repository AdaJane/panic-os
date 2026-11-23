#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
#
# Contract of persistence_state (persistence.sh) and of panicos-status.
#
#   persistence_state KERNEL_CMDLINE MOUNT_TARGETS -> active | disabled | missing
#
#   active    live-boot mounted a persistence volume
#   disabled  the operator chose a boot entry without persistence
#   missing   persistence was wanted but no volume was found: the case that
#             must be loud, because work would silently be lost at reboot

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LIB_DIR="$REPO_ROOT/live/config/includes.chroot/usr/lib/panicos"
  # shellcheck source=live/config/includes.chroot/usr/lib/panicos/constants.sh
  source "$LIB_DIR/constants.sh"
  # shellcheck source=live/config/includes.chroot/usr/lib/panicos/persistence.sh
  source "$LIB_DIR/persistence.sh"
  WANTED='boot=live components persistence persistence-label=panicos-persist'
  LIVE_MOUNTS=$'/\n/run/live/medium\n/run/live/rootfs/filesystem.squashfs'
}

@test "state: active when a persistence volume is mounted" {
  run persistence_state "$WANTED" "$LIVE_MOUNTS"$'\n/run/live/persistence/sdb3'
  [ "$status" -eq 0 ]
  [ "$output" = "$PANICOS_PERSISTENCE_ACTIVE" ]
}

@test "state: missing when persistence was requested but nothing is mounted" {
  run persistence_state "$WANTED" "$LIVE_MOUNTS"
  [ "$output" = "$PANICOS_PERSISTENCE_MISSING" ]
}

@test "state: disabled when the boot entry says nopersistence" {
  run persistence_state "$WANTED toram nopersistence" "$LIVE_MOUNTS"
  [ "$output" = "$PANICOS_PERSISTENCE_DISABLED" ]
}

@test "state: disabled when the command line never asked for persistence" {
  run persistence_state 'boot=live components' "$LIVE_MOUNTS"
  [ "$output" = "$PANICOS_PERSISTENCE_DISABLED" ]
}

@test "state: a parameter that merely contains the word does not count" {
  run persistence_state 'boot=live persistence-label=panicos-persist' "$LIVE_MOUNTS"
  [ "$output" = "$PANICOS_PERSISTENCE_DISABLED" ]
}

@test "state: the persistence mount directory itself is not a volume" {
  run persistence_state "$WANTED" "$LIVE_MOUNTS"$'\n/run/live/persistence'
  [ "$output" = "$PANICOS_PERSISTENCE_MISSING" ]
}
