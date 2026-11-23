#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
#
# Every file in the repository says which licence it is under.
#
# The repository's own work is MIT. The few files adapted from Debian's
# live-build carry that project's GPL-3.0-or-later instead. A file with no
# statement at all leaves a reader guessing, so it fails this test.

readonly TAG='SPDX-License-Identifier:'
readonly LICENCE_MIT=MIT
readonly LICENCE_GPL=GPL-3.0-or-later

# Files that cannot or need not carry a tag, one per line, with the reason.
readonly EXEMPT='
LICENSE                                    the MIT licence text itself
LICENSES/GPL-3.0-or-later.txt              the GPL licence text itself
README.md                                  prose; covered by LICENSE
live/keyrings/claude-code.asc              Anthropic public key, not our work
live/keyrings/mozilla.asc                  public key of Mozilla archive, not our work
live/config/includes.chroot/etc/issue      shown verbatim at the login prompt
live/config/includes.chroot/etc/motd       shown verbatim at login
'

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# Every file that is part of the repository: not build output, not git's own.
repository_files() {
  (cd "$REPO_ROOT" && find . \( -path ./out -o -path ./.git \) -prune -o -type f -print) \
    | sed 's|^\./||' | LC_ALL=C sort
}

exempt_files() {
  awk 'NF { print $1 }' <<< "$EXEMPT" | LC_ALL=C sort
}

tagged_as() {
  local -r licence=$1
  (cd "$REPO_ROOT" && grep --recursive --files-with-matches --fixed-strings \
    --exclude-dir=out --exclude-dir=.git "$TAG $licence" .) | sed 's|^\./||' | LC_ALL=C sort
}

@test "every file carries a licence tag, unless listed as exempt" {
  untagged="$(comm -23 <(repository_files) <(exempt_files) \
    | while read -r file; do
        grep --quiet --fixed-strings "$TAG" "$REPO_ROOT/$file" || printf '%s\n' "$file"
      done)"
  if [[ -n $untagged ]]; then
    echo "no licence tag in:"
    echo "$untagged"
    return 1
  fi
}

@test "every exempt file still exists" {
  missing="$(comm -13 <(repository_files) <(exempt_files))"
  [ -z "$missing" ]
}

@test "the GPL files are exactly the ones adapted from live-build" {
  expected=$'live/config/bootloaders/isolinux/isolinux.cfg\nscripts/grub-utilities.cfg'
  # This test names the GPL tag itself, so it is left out of the comparison.
  actual="$(tagged_as "$LICENCE_GPL" | grep --invert-match '^tests/unit/licensing.bats$')"
  [ "$actual" = "$expected" ]
}

@test "both licence texts are present" {
  grep --quiet 'MIT License' "$REPO_ROOT/LICENSE"
  grep --quiet 'GNU GENERAL PUBLIC LICENSE' "$REPO_ROOT/LICENSES/GPL-3.0-or-later.txt"
}
