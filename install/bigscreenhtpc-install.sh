#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Giulio (giukio)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://invent.kde.org/plasma/plasma-bigscreen

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_arch_based() {
  msg_info "Installing Plasma Bigscreen"
  $STD pacman -S --needed --noconfirm \
    mesa \
    vulkan-intel \
    intel-media-driver \
    plasma-desktop \
    plasma-workspace \
    kwin \
    plasma-bigscreen \
    plasma-nano \
    plasma-pa \
    plasma-nm \
    qt6-wayland \
    noto-fonts \
    ttf-liberation \
    seatd
  msg_ok "Installed Plasma Bigscreen"

  msg_info "Creating htpc user"
  useradd -m -G video,render,seat -s /bin/bash htpc
  loginctl enable-linger htpc
  systemctl enable -q --now seatd
  msg_ok "Created htpc user"

  msg_info "Creating Bigscreen session"
  cat <<'EOF' >/usr/local/bin/htpc-wait-drm.sh
#!/bin/bash
set -euo pipefail
RUNTIME_DIR="${XDG_RUNTIME_DIR:?}"
ENV_FILE="${RUNTIME_DIR}/htpc-drm.env"
mkdir -p "$RUNTIME_DIR"

pick_card() {
  local card base st
  for card in /dev/dri/card1 /dev/dri/card0 /dev/dri/card*; do
    [[ -e "$card" ]] || continue
    base=$(basename "$card")
    for st in /sys/class/drm/"${base}"-*/status; do
      [[ -f "$st" ]] || continue
      if [[ "$(cat "$st" 2>/dev/null || true)" == "connected" ]]; then
        printf '%s\n' "$card"
        return 0
      fi
    done
  done
  for card in /dev/dri/card1 /dev/dri/card0 /dev/dri/card*; do
    [[ -e "$card" ]] || continue
    printf '%s\n' "$card"
    return 0
  done
  return 1
}

deadline=$((SECONDS + 90))
card=""
while ((SECONDS < deadline)); do
  if card=$(pick_card); then
    base=$(basename "$card")
    connected=0
    for st in /sys/class/drm/"${base}"-*/status; do
      [[ -f "$st" ]] || continue
      if [[ "$(cat "$st" 2>/dev/null || true)" == "connected" ]]; then
        connected=1
        break
      fi
    done
    if ((connected == 1)) || ((SECONDS > deadline - 15)); then
      umask 077
      printf 'KWIN_DRM_DEVICES=%s\n' "$card" >"$ENV_FILE"
      echo "htpc-wait-drm: using $card (connected=$connected)"
      exit 0
    fi
  fi
  sleep 1
done

echo "htpc-wait-drm: timed out waiting for DRM" >&2
exit 1
EOF

  cat <<'EOF' >/usr/local/bin/htpc-start-plasma-bigscreen
#!/bin/bash
set -euo pipefail
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export XDG_CURRENT_DESKTOP=KDE
export PLASMA_DEFAULT_SHELL=org.kde.plasma.bigscreen
if [[ -f "${XDG_RUNTIME_DIR}/htpc-drm.env" ]]; then
  # shellcheck disable=SC1091
  source "${XDG_RUNTIME_DIR}/htpc-drm.env"
fi
if [[ -z "${KWIN_DRM_DEVICES:-}" ]]; then
  echo "htpc-start-plasma-bigscreen: no DRM device selected" >&2
  exit 1
fi
echo "htpc-start-plasma-bigscreen: KWIN_DRM_DEVICES=${KWIN_DRM_DEVICES}"
exec /usr/lib/plasma-dbus-run-session-if-needed /usr/bin/startplasma-wayland
EOF
  chmod 755 /usr/local/bin/htpc-wait-drm.sh /usr/local/bin/htpc-start-plasma-bigscreen

  cat <<'EOF' >/etc/systemd/user/plasma-bigscreen-htpc.service
[Unit]
Description=Plasma Bigscreen HTPC session
After=basic.target

[Service]
Type=simple
ExecStartPre=/usr/local/bin/htpc-wait-drm.sh
ExecStart=/usr/local/bin/htpc-start-plasma-bigscreen
Restart=on-failure
RestartSec=5
TimeoutStartSec=180
Environment=XDG_SESSION_TYPE=wayland
Environment=QT_QPA_PLATFORM=wayland
Environment=XDG_CURRENT_DESKTOP=KDE
Environment=PLASMA_DEFAULT_SHELL=org.kde.plasma.bigscreen

[Install]
WantedBy=default.target
EOF
  systemctl --global enable plasma-bigscreen-htpc.service
  msg_ok "Created Bigscreen session"

  if [[ -z "${var_flatpak:-}" ]]; then
    if prompt_confirm "Enable Flatpak support?" "n" 60; then
      var_flatpak=yes
    else
      var_flatpak=no
    fi
  fi
  if [[ "${var_flatpak}" == "yes" ]]; then
    msg_info "Installing Flatpak"
    $STD pacman -S --needed --noconfirm flatpak
    $STD flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    msg_ok "Installed Flatpak"
    if [[ -z "${var_jellyfin:-}" ]]; then
      if prompt_confirm "Install the Jellyfin Flatpak?" "n" 60; then
        var_jellyfin=yes
      else
        var_jellyfin=no
      fi
    fi
    if [[ -z "${var_vacuumtube:-}" ]]; then
      if prompt_confirm "Install the VacuumTube (YouTube) Flatpak?" "n" 60; then
        var_vacuumtube=yes
      else
        var_vacuumtube=no
      fi
    fi
  else
    var_jellyfin=no
    var_vacuumtube=no
  fi

  msg_info "Installing HDMI audio support"
    $STD pacman -S --needed --noconfirm pipewire wireplumber pipewire-pulse pipewire-alsa alsa-utils
    usermod -aG audio htpc
    cat <<'EOF' >/usr/local/bin/htpc-audio-hdmi.sh
#!/bin/bash
set -euo pipefail
card=""
device=""
while read -r line; do
  if [[ "$line" =~ ^card\ ([0-9]+): ]]; then
    card="${BASH_REMATCH[1]}"
  fi
  if [[ -n "$card" && "$line" =~ device\ ([0-9]+):.*(HDMI|DP) ]]; then
    device="${BASH_REMATCH[1]}"
    break
  fi
done < <(aplay -l 2>/dev/null || true)
if [[ -z "$card" || -z "$device" ]]; then
  echo "htpc-audio-hdmi: no HDMI/DP playback device in aplay -l" >&2
  exit 1
fi
pactl load-module module-alsa-sink device="hw:${card},${device}" sink_name=hdmi_tv sink_properties=device.description=HDMI_TV || true
pactl set-default-sink hdmi_tv || true
EOF
    chmod 755 /usr/local/bin/htpc-audio-hdmi.sh
    cat <<'EOF' >/etc/systemd/user/htpc-audio-hdmi.service
[Unit]
Description=HTPC HDMI audio sink
After=pipewire.service pipewire-pulse.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/htpc-audio-hdmi.sh
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF
  systemctl --global enable htpc-audio-hdmi.service
  msg_ok "Installed HDMI audio support"

  if [[ -z "${var_cec:-}" ]]; then
    if prompt_confirm "Pass through the HDMI-CEC adapter (/dev/cec0)?" "n" 60; then
      var_cec=yes
    else
      var_cec=no
    fi
  fi
  if [[ "${var_cec}" == "yes" ]]; then
    msg_info "Installing CEC support"
    $STD pacman -S --needed --noconfirm libcec v4l-utils
    usermod -aG input htpc
    install -d -o htpc -g htpc /home/htpc/.config
    cat <<'EOF' >/home/htpc/.config/plasma-bigscreen-inputhandlerrc
[General]
CecEnabled=true
GameControllerEnabled=false

[CECRemote]
OSDName=HTPC
EOF
    chown htpc:htpc /home/htpc/.config/plasma-bigscreen-inputhandlerrc
    cat <<'EOF' >/etc/systemd/user/htpc-cec-inputhandler.service
[Unit]
Description=Plasma Bigscreen CEC input handler
After=graphical-session.target

[Service]
Type=simple
ExecStartPre=/bin/sleep 5
Environment=PLASMA_PLATFORM=mediacenter
ExecStart=/usr/bin/plasma-bigscreen-inputhandler
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF
    systemctl --global enable htpc-cec-inputhandler.service
    msg_ok "Installed CEC support"
  fi

  if [[ -z "${var_kdeconnect:-}" ]]; then
    if prompt_confirm "Install KDE Connect?" "n" 60; then
      var_kdeconnect=yes
    else
      var_kdeconnect=no
    fi
  fi
  if [[ "${var_kdeconnect}" == "yes" ]]; then
    msg_info "Installing KDE Connect"
    $STD pacman -S --needed --noconfirm kdeconnect
    install -d /etc/systemd/user/kdeconnectd.service.d
    cat <<'EOF' >/etc/systemd/user/kdeconnectd.service.d/htpc-tv.conf
[Service]
Environment=PLASMA_PLATFORM=mediacenter
EOF
    msg_ok "Installed KDE Connect"
  fi

  if [[ "${var_kdeconnect}" == "yes" || "${var_cec}" == "yes" ]]; then
    msg_info "Preferring the KDE desktop portal"
    install -d -o htpc -g htpc /home/htpc/.config/xdg-desktop-portal /home/htpc/.config/environment.d
    cat <<'EOF' >/home/htpc/.config/xdg-desktop-portal/portals.conf
[preferred]
default=kde
EOF
    cat <<'EOF' >/home/htpc/.config/environment.d/90-htpc-kde.conf
XDG_CURRENT_DESKTOP=KDE
EOF
    chown -R htpc:htpc /home/htpc/.config/xdg-desktop-portal /home/htpc/.config/environment.d
    msg_ok "Preferred the KDE desktop portal"
  fi

  if [[ -z "${var_steam:-}" ]]; then
    if prompt_confirm "Install Steam (enables the Arch multilib repository)?" "n" 60; then
      var_steam=yes
    else
      var_steam=no
    fi
  fi
  if [[ "${var_steam}" == "yes" ]]; then
    msg_info "Installing Steam"
    if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
      cat <<'EOF' >>/etc/pacman.conf

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
    fi
    $STD pacman -Sy --needed --noconfirm steam
    msg_ok "Installed Steam"
  fi

  if [[ -z "${var_dpms:-}" ]]; then
    if prompt_confirm "Disable screen blanking and the screen locker?" "n" 60; then
      var_dpms=yes
    else
      var_dpms=no
    fi
  fi

  cat <<EOF >/etc/bigscreen-htpc.choices
flatpak=${var_flatpak}
jellyfin=${var_jellyfin}
vacuumtube=${var_vacuumtube}
cec=${var_cec}
kdeconnect=${var_kdeconnect}
steam=${var_steam}
dpms=${var_dpms}
EOF

  systemctl start "user@$(id -u htpc).service"

  if [[ "${var_dpms}" == "yes" ]]; then
    msg_info "Disabling screen blanking"
    systemd-run --uid="$(id -u htpc)" --pipe --wait --collect \
      -p Environment=XDG_RUNTIME_DIR=/run/user/$(id -u htpc) \
      -p Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u htpc)/bus \
      /usr/bin/kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false || true
    systemd-run --uid="$(id -u htpc)" --pipe --wait --collect \
      -p Environment=XDG_RUNTIME_DIR=/run/user/$(id -u htpc) \
      -p Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u htpc)/bus \
      /usr/bin/kwriteconfig6 --file powermanagementprofilesrc --group AC --group DPMSControl --key idleTime 0 || true
    msg_ok "Disabled screen blanking"
  fi

  if [[ "${var_kdeconnect}" == "yes" ]]; then
    msg_info "Looking for KDE Connect devices"
    uid=$(id -u htpc)
    systemd-run --uid="$uid" --pipe --wait --collect \
      -p Environment=XDG_RUNTIME_DIR=/run/user/$uid \
      -p Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
      /usr/bin/kdeconnect-cli --refresh || true
    echo "On the phone, open KDE Connect and make this HTPC visible on the same LAN."
    echo "Then list devices with:"
    echo "  kdeconnect-cli --list-available"
    echo "Pair one with:"
    echo "  kdeconnect-cli --pair -d <device-id>"
    if [[ -z "${var_kdeconnect_device:-}" ]] && [[ -t 0 ]]; then
      read -r -t 60 -p "Device id to pair now (empty to skip): " var_kdeconnect_device || true
    fi
    if [[ -n "${var_kdeconnect_device:-}" ]]; then
      systemd-run --uid="$uid" --pipe --wait --collect \
        -p Environment=XDG_RUNTIME_DIR=/run/user/$uid \
        -p Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
        /usr/bin/kdeconnect-cli --pair -d "$var_kdeconnect_device" || true
      echo "Accept the pairing request on the phone."
    fi
    msg_ok "KDE Connect is ready to pair"
  fi
}

run_os_setup

motd_ssh
customize
cleanup_lxc
