# SPDX-License-Identifier: MIT
# Warn at every login shell if this stick is not keeping state. Silent when
# all is well. On the desktop the same check opens a terminal, see
# /etc/xdg/autostart/panicos-status.desktop.
panicos_status="$(panicos-status)" || printf '\n%s\n\n' "$panicos_status"
unset panicos_status
