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
  systemctl start "user@$(id -u htpc).service"
  msg_ok "Created Bigscreen session"
}

run_os_setup

motd_ssh
customize
cleanup_lxc
