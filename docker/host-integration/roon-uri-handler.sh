#!/usr/bin/env bash
#
# Host-side handler for the roon:// URL scheme. Registered as the system default
# for x-scheme-handler/roon by install.sh. When you finish signing in, the host
# browser hits roon://login?code=... — this forwards it INTO the container so the
# running Roon completes login. (Delivering the code to the running instance is
# the one thing Roon's browser login needs, and Wine can't do it natively.)
#
set -euo pipefail
url="${1:-}"
container="${ROON_CONTAINER:-roon-on-wine}"
# -d: run detached so the browser's launch returns immediately while roon-open
# forwards + reaps in the background.
exec docker exec -d "$container" /usr/local/bin/roon-open "$url"
