#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
#
# Contract of claude_offer_due (claude.sh): when the first-startup offer to
# install Claude Code is shown.
#
#   claude_offer_due PERSISTENCE_STATE INSTALLED DECLINED
#
# It succeeds only when all three hold:
#   - persistence is active, so the install and the sign-in survive a reboot
#   - Claude Code is not installed yet
#   - the operator has not already said no

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LIB_DIR="$REPO_ROOT/live/config/includes.chroot/usr/lib/panicos"
  # shellcheck source=live/config/includes.chroot/usr/lib/panicos/constants.sh
  source "$LIB_DIR/constants.sh"
  # shellcheck source=live/config/includes.chroot/usr/lib/panicos/claude.sh
  source "$LIB_DIR/claude.sh"
}

# The whole truth table: state, installed, declined -> due?
readonly TRUTH_TABLE='
active    no   no   due
active    no   yes  not-due
active    yes  no   not-due
active    yes  yes  not-due
missing   no   no   not-due
missing   yes  no   not-due
disabled  no   no   not-due
disabled  no   yes  not-due
'

@test "offer: due only with active persistence, not installed, not declined" {
  local state installed declined expected actual rows=0
  while read -r state installed declined expected; do
    [[ -n $state ]] || continue
    if claude_offer_due "$state" "$installed" "$declined"; then actual=due; else actual=not-due; fi
    if [[ $actual != "$expected" ]]; then
      echo "state=$state installed=$installed declined=$declined: expected $expected, got $actual"
      return 1
    fi
    rows=$((rows + 1))
  done <<< "$TRUTH_TABLE"
  [ "$rows" -eq 8 ]
}

@test "offer: the table's words are the constants the code uses" {
  [ "$PANICOS_PERSISTENCE_ACTIVE" = active ]
  [ "$PANICOS_PERSISTENCE_MISSING" = missing ]
  [ "$PANICOS_PERSISTENCE_DISABLED" = disabled ]
  [ "$PANICOS_YES" = yes ]
  [ "$PANICOS_NO" = no ]
}

@test "declined: remembered through a marker file under the config directory" {
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  [ "$(claude_declined)" = "$PANICOS_NO" ]
  remember_claude_declined
  [ "$(claude_declined)" = "$PANICOS_YES" ]
}

@test "installed: follows whether the claude command exists" {
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  [ "$(claude_installed)" = "$PANICOS_NO" ]
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  [ "$(claude_installed)" = "$PANICOS_YES" ]
}

# --- panicos-claude-offer --due ----------------------------------------------
#
# Exit 0 means "show the offer", so anything that is not a clear yes must be
# a different status, and "cannot tell" must not look like "no".

readonly EX_CANNOT_TELL=2

@test "offer --due: without HOME it says so and exits as 'cannot tell'" {
  bats_require_minimum_version 1.5.0
  OFFER="$REPO_ROOT/live/config/includes.chroot/usr/bin/panicos-claude-offer"
  run --separate-stderr env --unset=HOME --unset=XDG_CONFIG_HOME "$OFFER" --due
  [ "$status" -eq "$EX_CANNOT_TELL" ]
  [[ "$stderr" == *"HOME"* ]]
}

@test "offer: an unknown option is a usage error" {
  OFFER="$REPO_ROOT/live/config/includes.chroot/usr/bin/panicos-claude-offer"
  run "$OFFER" --bogus
  [ "$status" -eq 64 ]
}
