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
build_container
description

msg_ok "Completed successfully!"
msg_custom "🚀" "${GN}" "Bigscreen HTPC setup has been successfully initialized!"
