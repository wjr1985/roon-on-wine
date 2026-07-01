#!/usr/bin/env bash
#
# Bridge Roon's "open this URL" actions (login page, help/artist links, …) to the
# HOST browser. The container has no browser, so Wine logs:
#   winebrowser:launch_app could not find a suitable app to open L"https://…"
# This tails the container log, extracts those URLs, and opens them with the host's
# xdg-open. run.sh starts this automatically; you can also run it standalone:
#
#   ./open-urls-on-host.sh
#
# (This is all that's needed for Roon login: the sign-in page opens here, you log
#  in, and Roon polls the cloud to authorize the running instance. The roon://
#  callback that browsers try afterward can't reach a Wine app and isn't needed.)
#
set -euo pipefail

CONTAINER="${1:-roon-on-wine}"

echo "Watching '$CONTAINER' for URLs to open on the host… (Ctrl-C to stop)"
docker logs -f "$CONTAINER" 2>&1 \
  | grep --line-buffered -oE 'could not find a suitable app to open L"[^"]+"' \
  | sed -u 's/.*L"//; s/"$//' \
  | while read -r url; do
      echo "→ opening on host: $url"
      setsid xdg-open "$url" >/dev/null 2>&1 &
    done
