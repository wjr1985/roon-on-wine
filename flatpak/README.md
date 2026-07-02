# Roon on Wine — Flatpak

Runs the Roon Windows desktop client on a **bundled, version-pinned Wine 10.0
stable** ([Kron4ek Wine-Builds](https://github.com/Kron4ek/Wine-Builds), checksum-pinned),
so host Wine upgrades can't break Roon. Same known-good stack as `../docker`,
but the sandbox replaces all the Docker plumbing:

| Docker | Flatpak |
|---|---|
| X cookie copy + socket mount | `--socket=x11` |
| Pulse socket mount + `PULSE_SERVER` | `--socket=pulseaudio` |
| `ipc: host` (X MIT-SHM) | `--share=ipc` |
| `network_mode: host` | `--share=network` |
| `init: true` zombie reaping | bwrap is the sandbox's PID 1 |
| `open-urls-on-host.sh` log-scraper | winebrowser → `xdg-open` → OpenURI portal |
| `host-integration/` roon:// handler + `docker exec` | `.desktop` `x-scheme-handler/roon` + FIFO hand-off |

This is an **unofficial, local build** — not affiliated with Roon Labs, and not
Flathub material (proprietary self-updating app, rolling installer URL). The
Roon installer is downloaded from roonlabs.com on first run.

## Build & install (no sudo)

```sh
# one-time tooling
flatpak install --user -y flathub org.freedesktop.Sdk//25.08 org.flatpak.Builder

# if you previously used ../docker: retire its host roon:// handler
../docker/host-integration/uninstall.sh

cd flatpak
flatpak run org.flatpak.Builder --user --install --force-clean \
    build io.github.wjr1985.RoonOnWine.yml
```

Requires `org.freedesktop.Platform//25.08` plus its `Compat.i386` and `GL32`
extensions (the builder/flatpak will pull them in as needed).

## Run

```sh
flatpak run io.github.wjr1985.RoonOnWine
```

- **First run:** a Wine prefix is created, then the Roon installer runs
  silently (NSIS `/S`) — no clicks needed. The installer hangs on a
  Windows-firewall step that's pointless on Linux, so the launcher tears it
  down once Roon has extracted, then starts Roon.
- **Login:** click Login in Roon; the sign-in page opens in your host browser.
  When the browser hits the `roon://login?code=…` callback, it launches a
  second (short-lived) instance of this flatpak which hands the URL to the
  running Roon via a FIFO — login completes, and the duplicate Roon window
  that Wine spawns as a side effect is reaped ~20 s later. One-time: login
  persists in the prefix.
- Everything (prefix, login) lives in `~/.var/app/io.github.wjr1985.RoonOnWine/data/`.

## Local audio zone (bundled native Roon Bridge)

Wine's RAATServer can never be discovered by a Roon Core — its SOOD discovery
responder misroutes replies out the loopback interface — so Roon's "This PC"
zone is impossible under Wine (in any packaging). Instead, on launch this
flatpak downloads (one-time) and runs **Roon's native Linux Bridge** alongside
the GUI. Your Core discovers it like any networked endpoint, and this machine's
ALSA devices appear as a zone named after the machine.

- Disable per-run with `--env=ROON_BRIDGE=0`, or persistently via
  `flatpak override --user --env=ROON_BRIDGE=0 io.github.wjr1985.RoonOnWine`.
- Bridge log: `~/.var/app/io.github.wjr1985.RoonOnWine/data/roonbridge.log`.
- Note: Roon on Linux plays to ALSA **hardware** devices (exclusive access
  while playing) — desktop audio and Roon playback can contend for the device.
- Zone without the GUI open: run the bridge headless via a systemd user unit:

  ```ini
  # ~/.config/systemd/user/roon-bridge.service
  [Unit]
  Description=Roon Bridge (flatpak, headless local audio zone)

  [Service]
  ExecStart=flatpak run --command=roon-launcher io.github.wjr1985.RoonOnWine bridge
  Restart=on-failure

  [Install]
  WantedBy=default.target
  ```

  `systemctl --user enable --now roon-bridge`. The GUI and the headless bridge
  coordinate via a lock file — whichever starts second skips the bridge.

## Knobs & debugging

```sh
flatpak run --env=SCALEFACTOR=1.5 io.github.wjr1985.RoonOnWine    # UI scale
flatpak run --env=WINEDEBUG=+winepulse,+mmdevapi io.github.wjr1985.RoonOnWine
flatpak run io.github.wjr1985.RoonOnWine winecfg                  # winecfg
flatpak run --command=sh io.github.wjr1985.RoonOnWine             # sandbox shell
flatpak override --user --env=SCALEFACTOR=1.25 io.github.wjr1985.RoonOnWine  # persist
```

Reset to a fresh install:

```sh
rm -rf ~/.var/app/io.github.wjr1985.RoonOnWine/data/prefix
```

Uninstall:

```sh
flatpak uninstall --user --delete-data io.github.wjr1985.RoonOnWine
```

## Why these pins (don't "fix" them)

- **Wine 10.0 stable**: 11.x aborts on the unimplemented
  `wminet_utils.dll.GetErrorInfo` during Roon's WMI drive scan; 10.x *staging*
  renders a washed-out UI. Only 10.0 stable avoids both.
- **`DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1`**: Roon bundles its own .NET;
  Wine's incomplete `icu.dll` aborts it otherwise.
- **`windows.media.mediacontrol` stays enabled**: disabling it (as old Wine
  setups did) makes Roon's now-playing reset crash on Wine 10.
- **`sound=pulse`** registry setting: audio goes out the pulseaudio socket
  (PipeWire-Pulse on the host).
