# Running Roon on Linux with Wine

This script makes it possible to run Roon on Wine. It creates a separate Wine instance in a folder; this is required for Roon.

Right now the script is very rudimentary: more stuff is coming soon. Keep in mind that you need the following programs to be installed on your Linux/FreeBSD system:

* wine
* winetricks
* winecfg
* wget

## Wine version

With respect to which version of Wine... this is a bit 'hit-and-miss'. 

# Install 
To install Roon just clone or download this repository and run <code>./install.sh</code>

Be patient, as installing the necessary components for Wine can take some time. Don't be scared of the messages that flood the console: drink a coffee and wait...

The installation is basically unattended. When the Roon installer starts you will need to click 'Install'.

When finished you can start Roon with <code>./start_my_roon_instance.sh</code>

## UI scaling issues
Wine is not capable (yet) to automatically scale the UI accoring screen resolution.
You can however manually adjust the scaling factor by editting the <code>start_my_roon_instance.sh</code> script, change the <code>SCALEFACTOR</code> variable and restart.
* Sensible values are betweein 1.0 and 2.0

# Running in Docker (version-pinned Wine)

On rolling-release distros the host Wine gets upgraded out from under you and
breaks Roon. The `docker/` setup runs the Roon **desktop GUI** on a **pinned
Wine 10.0 stable** inside a container, so host updates can never touch it. It's a
reproducible alternative to the scripts above.

**Prerequisites**
* `docker` (with the Compose plugin) installed, and your user in the `docker` group
* An X server / Xwayland session (the GUI is shown via the host X socket)

**Setup**
```bash
cd docker
cp .env.example .env          # then edit MUSIC_DIR (and UID/GID/GPU GIDs if not 1000/987/983)
./run.sh
```
On the **first run** the container builds the image, creates a fresh Wine prefix,
and launches the Roon installer — click **Install** in the window that appears
(the installer then auto-closes; it hangs on a Windows-firewall step Linux doesn't
need). It then starts Roon; subsequent runs launch straight into Roon. The Wine
prefix persists in `docker/prefix/`, so nothing re-downloads. `./run.sh` follows
the logs (Ctrl-C stops following, Roon keeps running); add `-d` to detach.
Stop Roon with `docker compose down`.

**Logging in** — click **Login** in Roon. Two bridges (both set up by `run.sh`)
make the browser round-trip work, since the container has no browser and Roon's
account login needs a callback delivered back to the *running* instance:

1. The sign-in page opens in your **host** browser (`open-urls-on-host.sh`
   forwards outbound URLs to it).
2. You sign in there; the browser then hits a `roon://login?code=…` callback. A
   host-side scheme handler (`host-integration/`, registered automatically by
   `run.sh`) forwards that callback **into** the container, where `roon-open`
   hands it to the running Roon — which completes login.

This is the piece the wider community hadn't cracked under Wine: Roon's
single-instance forwarding doesn't work there (the forward spawns a throwaway
duplicate that `roon-open` reaps, with `init: true` cleaning up the defunct
process). Your login persists in `docker/prefix/`, so it's a one-time step.

If your host desktop doesn't auto-register the handler, run it once manually:
`./host-integration/install.sh` (undo with `./host-integration/uninstall.sh`).

**What it wires up**
* Local + networked audio (host PipeWire-Pulse socket + host networking)
* GPU (`/dev/dri`) for OpenGL rendering (needs `ipc: host`, set in the compose file, for X shared memory)
* Your local music library, mounted read-only at `/music` (add it as a watched folder in Roon)
* URL bridges so login works: outbound links/login pages open in your host browser, and the `roon://` login callback is forwarded back into the container (see "Logging in")

**Why these specific settings** — getting a current Roon build to run took pinning
down several Wine/Roon interactions, all encoded in `docker/`:

| Setting | Fixes |
| --- | --- |
| Wine **10.0 stable** (not 11.x, not staging) | 11.x aborts on `wminet_utils.dll.GetErrorInfo` (WMI drive scan); staging washes out the UI colours |
| `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` | Wine's incomplete `icu.dll` otherwise aborts Roon's bundled .NET |
| `ipc: host` | X MIT-SHM (`X_ShmPutImage`) otherwise crashes Wine mid-render |
| `libegl1` in the image | missing `libEGL.so.1` (Wine falls back to GLX, but the warning is gone) |
| **Not** disabling `windows.media.mediacontrol` | disabling it (an old-Wine workaround) makes Roon's now-playing reset access-violate on Wine 10 |

**Changing the pinned Wine version** — edit `WINE_BRANCH` / `WINE_VERSION` in
`docker/.env` and re-run (`docker compose config` shows the resolved values). If a
future Wine reintroduces a crash, `WINEDLLOVERRIDES_RUN` in `.env` is a
per-launch override knob that needs no rebuild.

# Supported distro's
This scripts has been reported to work on:

* ArchLinux
* KDE Neon
* openSUSE
* Fedora
  * Don't use the WineHQ repo, but just the Fedora-native Wine (<code>sudo dnf install wine</code>)
* Ubuntu
* Linux Mint

Other OS:

* FreeBSD

<b> Ubuntu 20.04 (Focal Fossa) / Linux Mint 20x requires at least 'winehq-stable' (wine version 7.0+) or 'winehq-staging' (wine version 7.22+) </b>

If your distro is missing please leave a note!
