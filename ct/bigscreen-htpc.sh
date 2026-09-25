#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Giulio (giukio)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://invent.kde.org/plasma/plasma-bigscreen

APP="Bigscreen HTPC"
var_tags="${var_tags:-htpc;media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-archlinux}"
var_version="${var_version:-base}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"
export var_flatpak="${var_flatpak:-}"
export var_jellyfin="${var_jellyfin:-}"
export var_vacuumtube="${var_vacuumtube:-}"
export var_moonlight="${var_moonlight:-}"
export var_desktop="${var_desktop:-}"
export var_cec="${var_cec:-}"
export var_kdeconnect="${var_kdeconnect:-}"
export var_kdeconnect_device="${var_kdeconnect_device:-}"
export var_steam="${var_steam:-}"
export var_dpms="${var_dpms:-}"

header_info "$APP"
variables
color
catch_errors

update_arch_based() {
  if [[ ! -x /usr/local/bin/htpc-start-plasma-bigscreen ]]; then
    msg_error "No Bigscreen HTPC Installation Found!"
    exit
  fi
  msg_info "Updating Bigscreen HTPC"
  $STD pacman -Syu --noconfirm
  msg_ok "Updated Bigscreen HTPC"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  run_os_update
  exit
}

if [[ -t 0 ]] && command -v whiptail >/dev/null 2>&1; then
  whiptail --title "Bigscreen HTPC" --msgbox "\nPlasma Bigscreen uses the host GPU and shows on the connected display.\n\nPower the TV on before the container starts. With the display off, the session finds no output and fails.\n\nGPU passthrough defaults to Yes. Turn it off only if this host has no GPU." 14 72 || true
fi

start

if [[ -z "${var_flatpak:-}" ]]; then
  read -r -p "Enable Flatpak support? [y/N] " _ans </dev/tty || _ans=""
  case "${_ans,,}" in y | yes) var_flatpak=yes ;; *) var_flatpak=no ;; esac
fi
if [[ "${var_flatpak}" == "yes" && -z "${var_jellyfin:-}" ]]; then
  read -r -p "Install the Jellyfin Flatpak? [y/N] " _ans </dev/tty || _ans=""
  case "${_ans,,}" in y | yes) var_jellyfin=yes ;; *) var_jellyfin=no ;; esac
fi
if [[ "${var_flatpak}" == "yes" && -z "${var_vacuumtube:-}" ]]; then
  read -r -p "Install the VacuumTube (YouTube) Flatpak? [y/N] " _ans </dev/tty || _ans=""
  case "${_ans,,}" in y | yes) var_vacuumtube=yes ;; *) var_vacuumtube=no ;; esac
fi
if [[ "${var_flatpak}" == "yes" && -z "${var_moonlight:-}" ]]; then
  read -r -p "Install the Moonlight Flatpak? [y/N] " _ans </dev/tty || _ans=""
  case "${_ans,,}" in y | yes) var_moonlight=yes ;; *) var_moonlight=no ;; esac
fi
if [[ -z "${var_desktop:-}" ]]; then
  read -r -p "Install the full Plasma desktop as well? [y/N] " _ans </dev/tty || _ans=""
  case "${_ans,,}" in y | yes) var_desktop=yes ;; *) var_desktop=no ;; esac
fi
if [[ -z "${var_cec:-}" ]]; then
  read -r -p "Pass through the HDMI-CEC adapter? [y/N] " _ans </dev/tty || _ans=""
  case "${_ans,,}" in y | yes) var_cec=yes ;; *) var_cec=no ;; esac
fi
if [[ -z "${var_kdeconnect:-}" ]]; then
  read -r -p "Install KDE Connect? [y/N] " _ans </dev/tty || _ans=""
  case "${_ans,,}" in y | yes) var_kdeconnect=yes ;; *) var_kdeconnect=no ;; esac
fi
if [[ "${var_kdeconnect}" == "yes" && -z "${var_kdeconnect_device:-}" ]]; then
  read -r -p "KDE Connect device id to pair (empty to skip): " var_kdeconnect_device </dev/tty || var_kdeconnect_device=""
fi
if [[ -z "${var_steam:-}" ]]; then
  read -r -p "Install Steam? [y/N] " _ans </dev/tty || _ans=""
  case "${_ans,,}" in y | yes) var_steam=yes ;; *) var_steam=no ;; esac
fi
if [[ -z "${var_dpms:-}" ]]; then
  read -r -p "Disable screen blanking and the locker? [y/N] " _ans </dev/tty || _ans=""
  case "${_ans,,}" in y | yes) var_dpms=yes ;; *) var_dpms=no ;; esac
fi

build_container
pct set "$CTID" -onboot 0

choices="$(pct exec "$CTID" -- cat /etc/bigscreen-htpc.choices 2>/dev/null || true)"
need_reboot=1
audio_gid="$(pct exec "$CTID" -- getent group audio | cut -d: -f3)"
dev_index="$(pct config "$CTID" | sed -n 's/^dev\([0-9]*\):.*/\1/p' | sort -n | tail -1)"
dev_index=$((${dev_index:--1} + 1))
for node in /dev/snd/*; do
  [[ -c "$node" ]] || continue
  pct set "$CTID" -dev"${dev_index}" "$node,gid=${audio_gid}"
  dev_index=$((dev_index + 1))
done
if grep -q '^flatpak=yes$' <<<"$choices"; then
  pct set "$CTID" -features nesting=1,keyctl=1,fuse=1
fi
if grep -q '^cec=yes$' <<<"$choices"; then
  video_gid="$(pct exec "$CTID" -- getent group video | cut -d: -f3)"
  input_gid="$(pct exec "$CTID" -- getent group input | cut -d: -f3)"
  dev_index="$(pct config "$CTID" | sed -n 's/^dev\([0-9]*\):.*/\1/p' | sort -n | tail -1)"
  dev_index=$((${dev_index:--1} + 1))
  if [[ -e /dev/cec0 ]]; then
    pct set "$CTID" -dev"${dev_index}" "/dev/cec0,gid=${video_gid}"
    dev_index=$((dev_index + 1))
  else
    msg_warn "No /dev/cec0 on the host, CEC passthrough was skipped"
  fi
  modprobe uinput 2>/dev/null || true
  if [[ -e /dev/uinput ]]; then
    pct set "$CTID" -dev"${dev_index}" "/dev/uinput,gid=${input_gid},mode=0660"
  fi
  need_reboot=1
fi
if [[ "$need_reboot" -eq 1 ]]; then
  grep -q '^lxc.mount.auto:' "/etc/pve/lxc/${CTID}.conf" || echo "lxc.mount.auto: proc:rw sys:rw" >>"/etc/pve/lxc/${CTID}.conf"
  pct reboot "$CTID"
  for _ in $(seq 1 30); do
    pct exec "$CTID" -- true >/dev/null 2>&1 && break
    sleep 2
  done
fi
if grep -q '^jellyfin=yes$' <<<"$choices"; then
  pct exec "$CTID" -- flatpak install -y --noninteractive --system flathub com.github.iwalton3.jellyfin-media-player
fi
if grep -q '^vacuumtube=yes$' <<<"$choices"; then
  pct exec "$CTID" -- flatpak install -y --noninteractive --system flathub rocks.shy.VacuumTube
fi
if grep -q '^moonlight=yes$' <<<"$choices"; then
  pct exec "$CTID" -- flatpak install -y --noninteractive --system flathub com.moonlight_stream.Moonlight
fi

description

msg_ok "Completed successfully!"
msg_custom "🚀" "${GN}" "Bigscreen HTPC setup has been successfully initialized!"
