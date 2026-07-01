#!/usr/bin/env bash
#
# Launch Roon-on-Wine in Docker.
#   - builds the image on first use
#   - installs Roon on first run (click "Install" in the window that appears)
#   - starts Roon
#   - bridges any URL Roon opens (login page, help/artist links) to your HOST
#     browser, since the container has none
#
# Roon login: click Login in Roon, complete the sign-in in the browser window
# that opens on your host — Roon polls the cloud and logs the running instance in
# (no roon:// callback needed; that can't work under Wine and isn't required).
# The login persists in docker/prefix/, so it's a one-time thing.
#
# Usage: ./run.sh          (follow logs; Ctrl-C stops following, Roon keeps running)
#        ./run.sh -d       (detached; also runs the URL bridge in the background)
#
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "No .env found — copying from .env.example. Edit MUSIC_DIR before re-running." >&2
  cp .env.example .env
fi

# --- X authorization: copy the live cookie to a stable path (see docker-compose.yml) ---
XAUTH_SRC="${XAUTHORITY:-$HOME/.Xauthority}"
if [ -f "$XAUTH_SRC" ]; then
  cp -f "$XAUTH_SRC" ./.xauth && chmod 600 ./.xauth
else
  echo "WARNING: X cookie not found at '$XAUTH_SRC' — the Roon window may not open." >&2
fi
export XAUTH_HOST="$PWD/.xauth"
export DISPLAY="${DISPLAY:-:0}"

# --- Auto-detect host-specific values so this works on any machine ---
# (These override the defaults in .env; compose prefers the shell environment.)
export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"
rgid="$(getent group render 2>/dev/null | cut -d: -f3)"; [ -n "$rgid" ] && export RENDER_GID="$rgid"
vgid="$(getent group video  2>/dev/null | cut -d: -f3)"; [ -n "$vgid" ] && export VIDEO_GID="$vgid"

mkdir -p ./prefix

# Register the roon:// scheme handler (idempotent) so browser login redirects
# reach the container. Needed for Roon login; harmless otherwise.
if [ -x ./host-integration/install.sh ]; then
  ./host-integration/install.sh >/dev/null 2>&1 || true
fi

detach=0
for a in "$@"; do [ "$a" = "-d" ] || [ "$a" = "--detach" ] && detach=1; done

echo "Building/starting Roon…"
docker compose up --build -d

if [ "$detach" = "1" ]; then
  # Bridge stays alive in the background; stop it with: pkill -f open-urls-on-host.sh
  nohup ./open-urls-on-host.sh >/dev/null 2>&1 &
  echo "Roon running detached. URL bridge active (PID $!)."
  echo "Logs: docker logs -f roon-on-wine   |   Stop: docker compose down"
  exit 0
fi

# Foreground: run the URL bridge alongside a live log tail. Ctrl-C stops both;
# Roon itself keeps running (started detached above) until 'docker compose down'.
./open-urls-on-host.sh &
bridge=$!
trap 'kill "$bridge" 2>/dev/null || true' EXIT
echo "Roon is up. Any URL it opens (login page, links) will open in your host browser."
echo "Ctrl-C stops the log view; Roon keeps running. Stop it with: docker compose down"
docker compose logs -f || true