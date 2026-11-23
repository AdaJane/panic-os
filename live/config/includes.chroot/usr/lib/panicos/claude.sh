# shellcheck shell=bash
# SPDX-License-Identifier: MIT
#
# claude.sh — whether to offer Claude Code. Source it after constants.sh.
#
# Claude Code is Anthropic's proprietary software and may not be shipped in
# the image, so PanicOS offers to download it on first startup instead.

# claude_offer_due PERSISTENCE_STATE INSTALLED DECLINED -> succeeds if the
# first-startup offer should be shown. A pure function of its arguments.
#
# Only with active persistence: otherwise the download and the sign-in would
# be gone at the next boot, and the offer would come back every time.
claude_offer_due() {
  local -r persistence_state=$1 installed=$2 declined=$3
  [[ $persistence_state == "$PANICOS_PERSISTENCE_ACTIVE" \
    && $installed == "$PANICOS_NO" \
    && $declined == "$PANICOS_NO" ]]
}

# claude_installed -> PANICOS_YES or PANICOS_NO.
claude_installed() {
  if command -v -- "$PANICOS_CLAUDE_COMMAND" > /dev/null; then
    printf '%s\n' "$PANICOS_YES"
  else
    printf '%s\n' "$PANICOS_NO"
  fi
}

# The file whose existence records "do not offer again".
claude_declined_marker() {
  printf '%s/panicos/claude-code-declined\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# claude_declined -> PANICOS_YES or PANICOS_NO.
claude_declined() {
  if [[ -e "$(claude_declined_marker)" ]]; then
    printf '%s\n' "$PANICOS_YES"
  else
    printf '%s\n' "$PANICOS_NO"
  fi
}

remember_claude_declined() {
  local -r marker="$(claude_declined_marker)"
  mkdir -p "$(dirname "$marker")"
  : > "$marker"
}
