#!/usr/bin/env bash
#
# Roon-on-Wine launcher — the flatpak's `command`. Ports docker/entrypoint.sh
# (bootstrap + launch) and docker/roon-open (login-callback forwarding).
#
#   (none)      normal launch: install Roon on first run, then run it
#   roon://…    login-callback handler. The browser launches a SECOND flatpak
#               instance with the URL; it can't reach the primary instance's
#               wineserver (separate pid/tmp namespaces), so it hands the URL
#               over via a FIFO in $XDG_DATA_HOME — the same host-backed path
#               (~/.var/app/<id>/data) in every instance of this app.
#   install     force the one-time bootstrap (prefix + Roon installer)
#   winecfg     open winecfg (debugging)
#   shell       drop into a shell in the sandbox (debugging)
#   <cmd…>      run an arbitrary command in the wine environment
#
set -euo pipefail

export WINEPREFIX="${WINEPREFIX:-$XDG_DATA_HOME/prefix}"
export WINEARCH=win64
export WINEDEBUG="${WINEDEBUG:-fixme-all}"
# Roon bundles its own .NET (CoreCLR); Wine's icu.dll stub is missing functions
# the CLR calls (ulocdata_getCLDRVersion, uloc_canonicalize), which aborts Roon.
# Invariant globalization makes .NET skip ICU entirely.
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
SCALEFACTOR="${SCALEFACTOR:-1.0}"
# DLL overrides used when *launching* Roon. Empty by default: on Wine 10 the
# builtin windows.media.mediacontrol works, and DISABLING it (as older Wine
# setups did) makes Roon's now-playing reset access-violate.
RUN_OVERRIDES="${WINEDLLOVERRIDES_RUN:-}"

ROON_URL="http://download.roonlabs.com/builds/RoonInstaller64.exe"
FIFO="$XDG_DATA_HOME/roon-url.fifo"
LOCK="$XDG_DATA_HOME/roon-primary.lock"

roon_exe() {
  find "$WINEPREFIX/drive_c/users" \
    -path '*/AppData/Local/Roon/Application/Roon.exe' 2>/dev/null | head -1
}

install_roon() {
  echo "[roon-launcher] Bootstrapping Wine prefix at $WINEPREFIX (one-time)…"
  # mscoree=/mshtml= disabled -> skip the Gecko/Mono auto-install dialogs.
  # Roon ships its own .NET (CoreCLR) runtime, so wine-mono isn't needed.
  WINEDLLOVERRIDES="mscoree=,mshtml=" wineboot --init
  wineserver -w

  # Registry equivalents of the docker image's
  #   winetricks -q win10 ddr=opengl sound=pulse nocrashdialog
  # (all four are pure-registry verbs; doing them directly avoids bundling
  # winetricks and its cabextract dependency in the flatpak).
  echo "[roon-launcher] Applying Wine settings…"
  wine reg add 'HKCU\Software\Wine\Direct3D' /v DirectDrawRenderer /t REG_SZ /d opengl /f
  wine reg add 'HKCU\Software\Wine\Drivers' /v Audio /t REG_SZ /d pulse /f
  wine reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f
  wine winecfg -v win10
  wineserver -w

  echo "[roon-launcher] Downloading Roon installer…"
  tmp="$(mktemp -d)"
  wget -q -O "$tmp/RoonInstaller64.exe" "$ROON_URL"

  # /S = NSIS silent install: no window, no 'Install' click needed.
  echo "[roon-launcher] Running Roon installer (silent)…"
  wine "$tmp/RoonInstaller64.exe" /S >/dev/null 2>&1 &

  # The installer extracts Roon and then runs a Windows-Firewall helper that
  # hangs under Wine (and is pointless on Linux). So watch for Roon.exe to
  # appear, then tear the session down rather than waiting for the installer.
  echo "[roon-launcher] Waiting for Roon to extract…"
  for _ in $(seq 1 600); do
    [ -n "$(roon_exe)" ] && break
    sleep 2
  done
  if [ -n "$(roon_exe)" ]; then
    sleep 3   # let the last files settle
    echo "[roon-launcher] Roon extracted — closing installer (skipping the unneeded firewall step)."
  else
    echo "[roon-launcher] WARNING: Roon.exe not detected; closing installer anyway." >&2
  fi

  # -k kills the whole prefix session (installer, leftover explorer/services).
  # Don't use `wineserver -w` here: the installer leaves a virtual desktop
  # running, so waiting for "all Wine processes to exit" blocks forever.
  wineserver -k 2>/dev/null || true
  rm -rf "$tmp"
  echo "[roon-launcher] Bootstrap complete."
}

# Port of docker/roon-open: forward a roon:// URL to the RUNNING Roon. Wine's
# single-instance forwarding is broken — `wine Roon.exe <url>` DOES hand the
# arg to the running instance (login completes), but also spawns a throwaway
# duplicate. Reap safety: match only real Roon.exe processes with `pgrep -x`
# (exact name) — `pgrep -f` would also match the start.exe launcher, and
# killing that stops Roon. The killed duplicate's zombie is reaped by bwrap
# (the sandbox's PID 1) — the docker `init: true` equivalent.
deliver_url() {
  local url="$1" exe before p
  exe="$(roon_exe)"
  [ -z "$exe" ] && { echo "[roon-launcher] deliver: Roon.exe not found" >&2; return 1; }
  before="$(pgrep -x Roon.exe | sort -n || true)"
  wine "$exe" "$url" >>"$XDG_DATA_HOME/roon-open.log" 2>&1 &
  sleep 20
  for p in $(pgrep -x Roon.exe); do
    printf '%s\n' "$before" | grep -qx "$p" || kill "$p" 2>/dev/null || true
  done
}

# Blocking-read loop on the FIFO; each open waits for the next writer, so no
# inotify is needed. Runs in the primary instance, where the wineserver lives.
url_watcher() {
  local url
  while :; do
    if read -r url < "$FIFO"; then
      case "$url" in
        roon://*)
          echo "[roon-launcher] login callback: $url"
          deliver_url "$url" &
          ;;
      esac
    fi
  done
}

cmd="${1:-run}"
case "$cmd" in
  roon://*)
    # Secondary instance (browser callback). Hand off to the primary if one is
    # running (FIFO exists + lock is held), else cold-start Roon with the URL.
    if [ -p "$FIFO" ] && ! flock -n "$LOCK" true 2>/dev/null; then
      # timeout: don't hang forever if the reader vanished between checks.
      if timeout 5 bash -c 'printf "%s\n" "$1" > "$2"' _ "$cmd" "$FIFO"; then
        exit 0
      fi
    fi
    echo "[roon-launcher] no running instance; cold-starting Roon with the URL"
    exec "$0" run-with-url "$cmd"
    ;;

  run|run-with-url)
    # Single-instance guard: hold the lock for our whole lifetime.
    exec 9>"$LOCK"
    if ! flock -n 9; then
      echo "[roon-launcher] Roon on Wine is already running; not starting a second instance." >&2
      exit 1
    fi

    if [ -z "$(roon_exe)" ]; then
      install_roon
    fi
    exe="$(roon_exe)"
    if [ -z "$exe" ]; then
      echo "[roon-launcher] ERROR: Roon.exe not found after install — check the installer window." >&2
      exit 1
    fi

    # We hold the lock, so any leftover FIFO is stale — recreate it.
    rm -f "$FIFO"
    mkfifo -m 600 "$FIFO"
    url_watcher & watcher=$!
    trap 'kill "$watcher" 2>/dev/null || true; rm -f "$FIFO"' EXIT

    extra=()
    [ "$cmd" = run-with-url ] && extra=("${2:?run-with-url needs a URL}")
    echo "[roon-launcher] Starting Roon: $exe"
    # Foreground (not exec): the EXIT trap must tear down the watcher; when we
    # exit, bwrap (sandbox PID 1) dies and takes the wineserver with it.
    WINEDLLOVERRIDES="$RUN_OVERRIDES" wine "$exe" -scalefactor="$SCALEFACTOR" ${extra[@]+"${extra[@]}"}
    ;;

  install)
    install_roon
    ;;
  winecfg)
    exec winecfg
    ;;
  shell)
    exec bash
    ;;
  *)
    exec "$@"
    ;;
esac
