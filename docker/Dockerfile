# Roon desktop (Windows app) on a version-pinned Wine, in Docker.
#
# Why: the host distro (CachyOS, rolling) keeps upgrading Wine, and newer Wine
# (11.x) breaks Roon — a washed-out UI, and a hard crash where Roon's WMI drive
# enumeration calls the unimplemented wminet_utils.dll.GetErrorInfo and FailFasts.
# Pinning Wine here freezes a known-good stack so host upgrades can't touch it.
#
# The Wine version is the primary iteration knob. Community consensus (2026) is
# "Wine 10, not 11". Default below is the latest 10-series staging build.
# Override at build time:  --build-arg WINE_VERSION=10.0.0~bookworm-1 --build-arg WINE_BRANCH=stable

FROM debian:bookworm

# Wine 10.0 STABLE: dodges the wminet_utils WMI crash (Wine 11.x) AND the
# washed-out-colours bug that affects winehq-STAGING. Don't bump to 11.x.
ARG WINE_BRANCH=stable
ARG WINE_VERSION=10.0.0.0~bookworm-1
# Host user so the bind-mounted prefix/music aren't owned by root (billr = 1000).
ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive

# --- WineHQ repo (pinned) + 32-bit arch (Wine needs i386 even for a win64 prefix) ---
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget gnupg \
 && mkdir -pm755 /etc/apt/keyrings \
 && wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
 && wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources \
 && apt-get update \
 # The winehq-* metapackage can't drag in its exact-versioned deps on its own
 # ("held broken packages"), so pin the whole chain explicitly.
 && apt-get install -y --install-recommends \
      "winehq-${WINE_BRANCH}=${WINE_VERSION}" \
      "wine-${WINE_BRANCH}=${WINE_VERSION}" \
      "wine-${WINE_BRANCH}-amd64=${WINE_VERSION}" \
      "wine-${WINE_BRANCH}-i386:i386=${WINE_VERSION}" \
 && rm -rf /var/lib/apt/lists/*

# --- Runtime deps: GL/Vulkan (Roon renders via OpenGL), audio client, X client
#     libs, fonts, and helpers used during first-run install.
#     winetricks itself is fetched from upstream below (the apt package is in
#     'contrib' and is often too old to run current verbs). ---
RUN apt-get update && apt-get install -y --no-install-recommends \
      cabextract p7zip-full \
      libgl1 libglx-mesa0 libgl1-mesa-dri \
      libegl1 libegl-mesa0 libgles2 \
      mesa-vulkan-drivers libvulkan1 \
      libgl1:i386 libgl1-mesa-dri:i386 libegl1:i386 libegl-mesa0:i386 libvulkan1:i386 \
      mesa-utils \
      pulseaudio-utils \
      xauth x11-utils \
      fonts-liberation \
      winbind \
      procps \
 && rm -rf /var/lib/apt/lists/* \
 && wget -q -O /usr/local/bin/winetricks \
      https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
 && chmod +x /usr/local/bin/winetricks

# --- Non-root user matching the host UID/GID ---
RUN groupadd -g "${GID}" roon \
 && useradd -m -u "${UID}" -g "${GID}" -s /bin/bash roon

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY roon-open /usr/local/bin/roon-open
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/roon-open

USER roon
ENV WINEPREFIX=/prefix \
    WINEARCH=win64 \
    WINEDEBUG=fixme-all \
    WINEDLLOVERRIDES_RUN="" \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
    SCALEFACTOR=1.0

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["run"]
