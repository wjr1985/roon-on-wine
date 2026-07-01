#!/usr/bin/env bash
#
# Container entrypoint for Roon-on-Wine.
#
#   run       (default) install Roon on first run, then launch it
#   install   force the one-time bootstrap (prefix + Roon installer)
#   winecfg   open winecfg (debugging)
#   shell     drop into a bash shell (debugging)
#   <cmd...>  run an arbitrary command in the wine environment
#
set -euo pipefail

export WINEPREFIX="${WINEPREFIX:-/prefix}"
export WINEARCH="${WINEARCH:-win64}"
export WINEDEBUG="${WINEDEBUG:-fixme-all}"
SCALEFACTOR="${SCALEFACTOR:-1.0}"

# Wine and the PulseAudio client want a valid, user-owned XDG_RUNTIME_DIR.
# The host pulse socket is reached via PULSE_SERVER (set in compose), so this
# just needs to exist and be private to us.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

# Roon bundles its own .NET; Wine 10.x's icu.dll stub is missing functions the
# CLR calls (ulocdata_getCLDRVersion, uloc_canonicalize), which aborts Roon.
# Invariant globalization makes .NET skip ICU entirely.
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT="${DOTNET_SYSTEM_GLOBALIZATION_INVARIANT:-1}"

# DLL overrides used when *launching* Roon. Empty by default: on Wine 10.20 the
# builtin windows.media.mediacontrol works, and DISABLING it (as older Wine setups
# did) makes Roon's now-playing reset access-violate. Override via docker/.env if a
# future Wine needs it.
RUN_OVERRIDES="${WINEDLLOVERRIDES_RUN:-}"

ROON_URL="http://download.roonlabs.com/builds/RoonInstaller64.exe"

roon_exe() {
  find "$WINEPREFIX/drive_c/users" \
    -path '*/AppData/Local/Roon/Application/Roon.exe' 2>/dev/null | head -1
}

install_roon() {
  echo "[entrypoint] Bootstrapping Wine prefix at $WINEPREFIX (one-time)…"
  # mscoree=/mshtml= disabled -> skip the Gecko/Mono auto-install dialogs.
  # Roon ships its own .NET (CoreCLR) runtime, so wine-mono isn't needed.
  WINEDLLOVERRIDES="mscoree=,mshtml=" wineboot --init
  wineserver -w

  # Minimal Wine settings that still matter for Roon (ported from ../install.sh).
  # NOTE: sound=pulse (not alsa as the host script uses) — in the container there's
  # no ALSA hardware; audio is routed to the host PipeWire-Pulse socket (PULSE_SERVER).
  echo "[entrypoint] Applying winetricks settings…"
  winetricks -q win10 ddr=opengl sound=pulse nocrashdialog || true

  # --- Optional legacy .NET (Roon bundles its own; enable only if it complains) ---
  # winetricks -q dotnet7

  echo "[entrypoint] Downloading Roon installer…"
  tmp="$(mktemp -d)"
  wget -q --show-progress -O "$tmp/RoonInstaller64.exe" "$ROON_URL"

  echo "[entrypoint] Launching Roon installer — click 'Install' in the window that appears."
  wine "$tmp/RoonInstaller64.exe" >/dev/null 2>&1 &

  # The installer extracts Roon and then runs a Windows-Firewall helper that hangs
  # under Wine (and is pointless on Linux). So watch for Roon.exe to appear, then
  # tear the session down rather than waiting for the installer to "finish".
  echo "[entrypoint] Waiting for Roon to extract (click Install if you haven't)…"
  for _ in $(seq 1 600); do
    [ -n "$(roon_exe)" ] && break
    sleep 2
  done
  if [ -n "$(roon_exe)" ]; then
    sleep 3   # let the last files settle
    echo "[entrypoint] Roon extracted — closing installer (skipping the unneeded firewall step)."
  else
    echo "[entrypoint] WARNING: Roon.exe not detected; closing installer anyway." >&2
  fi

  # -k kills the whole prefix session (installer, leftover explorer/services).
  # Don't use `wineserver -w` here: the installer leaves a virtual desktop running,
  # so waiting for "all Wine processes to exit" blocks forever.
  wineserver -k 2>/dev/null || true
  rm -rf "$tmp"
  echo "[entrypoint] Bootstrap complete."
}

cmd="${1:-run}"
case "$cmd" in
  run)
    [ -z "$(roon_exe)" ] && install_roon
    exe="$(roon_exe)"
    if [ -z "$exe" ]; then
      echo "[entrypoint] ERROR: Roon.exe not found after install — check the installer window." >&2
      exit 1
    fi
    echo "[entrypoint] Starting Roon: $exe"
    exec env WINEDLLOVERRIDES="$RUN_OVERRIDES" wine "$exe" -scalefactor="$SCALEFACTOR"
    ;;
  install)
    install_roon
    ;;
  winecfg)
    exec winecfg
    ;;
  shell)
    exec /bin/bash
    ;;
  *)
    exec "$@"
    ;;
esac
