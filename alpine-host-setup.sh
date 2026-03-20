#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# alpine-host-setup.sh — bootstrap Alpine Linux as the lxcbox host
#
# Run once as root on a fresh Alpine install.
# Sets up: LXC, Wayland compositor (cage/labwc), PipeWire, GPU drivers,
# user session that boots directly into the LXC container.
#
# Target: Alpine Linux (edge or 3.19+), musl + OpenRC

set -o errexit
set -o nounset

LXCBOX_USER="${LXCBOX_USER:-${SUDO_USER:-}}"
LXCBOX_CONTAINER="${LXCBOX_CONTAINER:-mybox}"
LXCBOX_DEBIAN_RELEASE="${LXCBOX_DEBIAN_RELEASE:-bookworm}"
LXCBOX_INSTALL_DIR="${LXCBOX_INSTALL_DIR:-/opt/lxcbox}"

die() { printf >&2 "ERROR: %s\n" "$*"; exit 1; }
log() { printf "\033[32m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[33mWARN:\033[0m %s\n" "$*"; }

[ "$(id -ru)" -eq 0 ] || die "Run as root: sudo sh alpine-host-setup.sh"
[ -n "${LXCBOX_USER}" ] || die "Set LXCBOX_USER=youruser before running"

# ── 1. Enable Alpine edge repos ───────────────────────────────────────────────
log "Configuring Alpine repos ..."
cat > /etc/apk/repositories << REPOS
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
https://dl-cdn.alpinelinux.org/alpine/edge/testing
REPOS

apk update

# ── 2. Core host packages ─────────────────────────────────────────────────────
log "Installing core packages ..."
apk add --no-cache \
    lxc \
    lxc-templates \
    lxc-openrc \
    cgmanager \
    debootstrap \
    fakeroot \
    fakechroot \
    ca-certificates \
    dbus \
    dbus-openrc \
    eudev \
    eudev-openrc \
    udev-init-scripts \
    util-linux \
    e2fsprogs \
    shadow \
    bash \
    curl \
    wget \
    git \
    rsync

# ── 3. Wayland compositor ─────────────────────────────────────────────────────
# cage  = minimal kiosk Wayland compositor (single fullscreen app)
# labwc = openbox-style stacking Wayland compositor (more desktop-like)
# We install both; default is labwc for desktop use.
log "Installing Wayland stack ..."
apk add --no-cache \
    wayland \
    wayland-dev \
    wayland-protocols \
    wlroots \
    cage \
    labwc \
    foot \
    xwayland \
    xorg-server-xwayland

# ── 4. PipeWire ───────────────────────────────────────────────────────────────
log "Installing PipeWire ..."
apk add --no-cache \
    pipewire \
    pipewire-spa-bluez \
    pipewire-alsa \
    pipewire-pulse \
    wireplumber \
    alsa-utils \
    alsa-ucm-conf

# ── 5. GPU drivers ────────────────────────────────────────────────────────────
log "Installing GPU drivers ..."
# Mesa (Intel/AMD open source)
apk add --no-cache \
    mesa \
    mesa-gl \
    mesa-dri-gallium \
    mesa-vulkan-intel \
    mesa-vulkan-layers \
    vulkan-loader \
    libva \
    libva-intel-driver \
    libva-utils \
    intel-media-driver || warn "Some Intel GPU packages not found, continuing ..."

# NVIDIA: proprietary driver must be installed manually.
# Open kernel module is in testing; uncomment if needed:
# apk add --no-cache nvidia-open || warn "NVIDIA driver not found, skipping ..."

# ── 6. OpenRC services ────────────────────────────────────────────────────────
log "Enabling OpenRC services ..."
rc-update add dbus default
rc-update add udev sysinit
rc-update add lxc default

# ── 7. LXC configuration ─────────────────────────────────────────────────────
log "Configuring LXC ..."

# Allow unprivileged user namespaces (needed for rootless LXC)
cat > /etc/sysctl.d/99-lxc-userns.conf << SYSCTL
kernel.unprivileged_userns_clone = 1
user.max_user_namespaces = 15000
SYSCTL
sysctl -p /etc/sysctl.d/99-lxc-userns.conf || true

# Configure LXC default config for rootless containers
LXCBOX_USER_HOME="$(getent passwd "${LXCBOX_USER}" | cut -d: -f6)"
LXCBOX_USER_UID="$(id -u "${LXCBOX_USER}")"
LXCBOX_USER_GID="$(id -g "${LXCBOX_USER}")"

mkdir -p "${LXCBOX_USER_HOME}/.config/lxc"
cat > "${LXCBOX_USER_HOME}/.config/lxc/default.conf" << LXCDEFAULT
lxc.include = /etc/lxc/default.conf
lxc.idmap = u 0 100000 65536
lxc.idmap = g 0 100000 65536
LXCDEFAULT
chown -R "${LXCBOX_USER}:${LXCBOX_USER}" "${LXCBOX_USER_HOME}/.config"

# Subuid/subgid mappings for rootless LXC
if ! grep -q "^${LXCBOX_USER}:" /etc/subuid 2>/dev/null; then
    echo "${LXCBOX_USER}:100000:65536" >> /etc/subuid
fi
if ! grep -q "^${LXCBOX_USER}:" /etc/subgid 2>/dev/null; then
    echo "${LXCBOX_USER}:100000:65536" >> /etc/subgid
fi

# Give user permission to use lxc-start without sudo (via newuidmap/newgidmap)
# This is handled by the subuid/subgid entries above + lxc-user-nic config
cat >> /etc/lxc/lxc-usernet << LXCUSERNET
${LXCBOX_USER} veth lxcbr0 10
LXCUSERNET

# ── 8. Install lxcbox scripts ─────────────────────────────────────────────────
log "Installing lxcbox scripts to ${LXCBOX_INSTALL_DIR} ..."
mkdir -p "${LXCBOX_INSTALL_DIR}"

# Copy scripts from same directory as this setup script
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
for script in \
    lxcbox-create \
    lxcbox-enter \
    lxcbox-init \
    lxcbox-export \
    lxcbox-host-exec \
    lxcbox-snapshot \
    lxcbox-list \
    lxcbox-rm \
    lxcbox; do
    if [ -e "${SCRIPT_DIR}/${script}" ]; then
        install -m 755 "${SCRIPT_DIR}/${script}" "${LXCBOX_INSTALL_DIR}/${script}"
    else
        warn "${script} not found in ${SCRIPT_DIR}, skipping ..."
    fi
done

# Symlink to /usr/local/bin
for script in "${LXCBOX_INSTALL_DIR}"/lxcbox*; do
    name="$(basename "${script}")"
    ln -sf "${script}" "/usr/local/bin/${name}"
done

log "lxcbox scripts installed."

# ── 9. Auto-login + auto-start compositor ────────────────────────────────────
log "Configuring auto-login for ${LXCBOX_USER} ..."

# agetty auto-login on tty1
mkdir -p /etc/conf.d
cat > /etc/conf.d/agetty.tty1 << AGETTY
agetty_options="--autologin ${LXCBOX_USER} --noclear"
AGETTY

# User profile: start Wayland compositor + enter lxcbox on tty1 login
cat > "${LXCBOX_USER_HOME}/.profile" << PROFILE
# lxcbox auto-start
# On tty1: launch Wayland compositor which immediately enters the container
if [ "\$(tty)" = "/dev/tty1" ] && [ -z "\${WAYLAND_DISPLAY}" ]; then
    exec labwc -s "lxcbox-enter ${LXCBOX_CONTAINER}"
fi
PROFILE
chown "${LXCBOX_USER}:${LXCBOX_USER}" "${LXCBOX_USER_HOME}/.profile"

# labwc config: no decorations, start lxcbox-enter as the only client
LABWC_CONFIG_DIR="${LXCBOX_USER_HOME}/.config/labwc"
mkdir -p "${LABWC_CONFIG_DIR}"

cat > "${LABWC_CONFIG_DIR}/autostart" << AUTOSTART
# labwc autostart — launch the lxcbox container session
lxcbox-enter ${LXCBOX_CONTAINER} &
AUTOSTART

cat > "${LABWC_CONFIG_DIR}/rc.xml" << RCXML
<?xml version="1.0"?>
<labwc_config>
  <core>
    <decoration>none</decoration>
    <gap>0</gap>
  </core>
</labwc_config>
RCXML

chown -R "${LXCBOX_USER}:${LXCBOX_USER}" "${LABWC_CONFIG_DIR}"

# ── 10. PipeWire user session ─────────────────────────────────────────────────
log "Configuring PipeWire user session ..."

# PipeWire starts as a user service via XDG autostart
mkdir -p "${LXCBOX_USER_HOME}/.config/autostart"
cat > "${LXCBOX_USER_HOME}/.config/autostart/pipewire.desktop" << PWAUTOSTART
[Desktop Entry]
Type=Application
Name=PipeWire
Exec=pipewire
NoDisplay=true
PWAUTOSTART

cat > "${LXCBOX_USER_HOME}/.config/autostart/wireplumber.desktop" << WPAUTOSTART
[Desktop Entry]
Type=Application
Name=WirePlumber
Exec=wireplumber
NoDisplay=true
WPAUTOSTART
chown -R "${LXCBOX_USER}:${LXCBOX_USER}" "${LXCBOX_USER_HOME}/.config/autostart"

# ── 11. Create the default lxcbox container ───────────────────────────────────
log "Creating default lxcbox container '${LXCBOX_CONTAINER}' ..."
su -l "${LXCBOX_USER}" -c \
    "lxcbox-create --name '${LXCBOX_CONTAINER}' --release '${LXCBOX_DEBIAN_RELEASE}' --yes"

# ── Done ──────────────────────────────────────────────────────────────────────
log "Alpine host setup complete!"
cat << DONE

Next steps:
  1. Reboot the machine
  2. It will auto-login as ${LXCBOX_USER} on tty1
  3. labwc will start and immediately open lxcbox '${LXCBOX_CONTAINER}'
  4. You're in a full Debian environment on an Alpine host

To enter the container manually:
  lxcbox-enter ${LXCBOX_CONTAINER}

To snapshot before upgrades:
  lxcbox-snapshot create ${LXCBOX_CONTAINER} my-snapshot

Snapshots are automatic via apt pre-invoke hook (inside the container).

DONE
