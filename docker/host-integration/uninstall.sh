#!/usr/bin/env bash
# Remove the roon:// URL scheme handler registered by install.sh.
set -euo pipefail
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
rm -f "$apps/roon-on-wine.desktop"
update-desktop-database "$apps" >/dev/null 2>&1 || true
# Best-effort: clear the default association if it still points at us.
if [ "$(xdg-mime query default x-scheme-handler/roon 2>/dev/null)" = "roon-on-wine.desktop" ]; then
  xdg-mime default '' x-scheme-handler/roon >/dev/null 2>&1 || true
fi
echo "roon:// handler unregistered."
