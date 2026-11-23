#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
#
# Third-party apt archives configured in the image.
#
# Each archive is trusted through one key, named in its sources line with
# signed-by=, and for that archive only. The image trusts whatever key file
# is committed under live/keyrings/, so each is pinned here to the
# fingerprint its owner publishes.

bats_require_minimum_version 1.5.0

# Anthropic, "Verify the signing key": https://code.claude.com/docs/en/setup
readonly CLAUDE_CODE_KEY_FINGERPRINT=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
# Mozilla, "Install Firefox on Linux":
# https://support.mozilla.org/en-US/kb/install-firefox-linux
# The key is served from https://packages.mozilla.org/apt/repo-signing-key.gpg
# and belongs to Google's Artifact Registry, which hosts Mozilla's archive.
# Mozilla has discussed rotating it (bugzilla.mozilla.org, bug 1816076); when
# that happens this test fails and both the key and this value need renewing.
readonly MOZILLA_KEY_FINGERPRINT=35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3

readonly IMAGE_KEYRING_DIR=/etc/apt/keyrings

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ARCHIVES="$REPO_ROOT/live/config/archives"
  KEYRINGS="$REPO_ROOT/live/keyrings"
  export GNUPGHOME="$BATS_TEST_TMPDIR/gnupg"
  mkdir --mode=0700 "$GNUPGHOME"
}

fingerprints() {
  gpg --show-keys --with-colons "$1" | awk -F: '$1 == "fpr" { print $10 }'
}

source_lines() {
  grep --no-filename --extended-regexp '^deb(-src)? ' "$ARCHIVES"/*.list
}

@test "the Claude Code archive key is the one Anthropic publishes" {
  # gpg announces its new keyring on stderr; only stdout carries the key.
  run --separate-stderr fingerprints "$KEYRINGS/claude-code.asc"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$CLAUDE_CODE_KEY_FINGERPRINT" ]
}

@test "the Mozilla archive key is the one Mozilla publishes" {
  run --separate-stderr fingerprints "$KEYRINGS/mozilla.asc"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$MOZILLA_KEY_FINGERPRINT" ]
}

@test "every archive is fetched over HTTPS" {
  run source_lines
  [ "$status" -eq 0 ]
  for line in "${lines[@]}"; do
    [[ "$line" == *" https://"* ]]
  done
}

@test "every archive names its own key, and that key is in live/keyrings" {
  run source_lines
  [ "$status" -eq 0 ]
  for line in "${lines[@]}"; do
    [[ "$line" =~ \[signed-by=$IMAGE_KEYRING_DIR/([a-z0-9-]+\.asc)\] ]]
    [ -r "$KEYRINGS/${BASH_REMATCH[1]}" ]
  done
}

@test "no key is trusted for every archive" {
  # live-build installs config/archives/*.key* into apt's global keyring.
  run find "$ARCHIVES" -name '*.key*'
  [ -z "$output" ]
}
