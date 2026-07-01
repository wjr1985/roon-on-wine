#!/usr/bin/env bash
#
# Register the roon:// URL scheme handler for the current user, so browser login
# redirects reach the Dockerized Roon. Idempotent; run.sh calls this for you.
# Undo with ./uninstall.sh.
#
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
desktop="$apps/roon-on-wine.desktop"

mkdir -p "$apps"
cat > "$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Roon (Docker) URL Handler
Comment=Forward roon:// login callbacks into the Dockerized Roon
Exec=$here/roon-uri-handler.sh %u
NoDisplay=true
Terminal=false
MimeType=x-scheme-handler/roon;
EOF

update-desktop-database "$apps" >/dev/null 2>&1 || true
xdg-mime default roon-on-wine.desktop x-scheme-handler/roon >/dev/null 2>&1 || true
echo "roon:// handler registered -> $(xdg-mime query default x-scheme-handler/roon 2>/dev/null)"
