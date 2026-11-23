# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# persistence.sh — what this boot is doing about persistence. Source it after
# constants.sh.

# persistence_state KERNEL_CMDLINE MOUNT_TARGETS -> one of the
# PANICOS_PERSISTENCE_* states (see constants.sh).
#
# A pure function of its arguments: the kernel command line, and the mount
# points of the running system, one per line.
persistence_state() {
  local -r cmdline=$1 mount_targets=$2
  if grep --quiet "^$PANICOS_PERSISTENCE_MOUNT_DIR/." <<< "$mount_targets"; then
    printf '%s\n' "$PANICOS_PERSISTENCE_ACTIVE"
  elif [[ " $cmdline " == *' persistence '* && " $cmdline " != *' nopersistence '* ]]; then
    printf '%s\n' "$PANICOS_PERSISTENCE_MISSING"
  else
    printf '%s\n' "$PANICOS_PERSISTENCE_DISABLED"
  fi
}

# current_persistence_state -> persistence_state of the running system.
current_persistence_state() {
  persistence_state "$(< /proc/cmdline)" \
    "$(findmnt --list --noheadings --output TARGET)"
}
