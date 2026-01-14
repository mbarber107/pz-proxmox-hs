#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: [Your GitHub Username]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://projectzomboid.com/

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"

APP="Project-Zomboid"
var_tags="${var_tags:-gaming}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/pzserver ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Get current installed version
  CURRENT_BUILD="unknown"
  if [[ -f /opt/pzserver/.pz_build_version ]]; then
    CURRENT_BUILD=$(cat /opt/pzserver/.pz_build_version)
  fi

  msg_info "Current installed build: ${CURRENT_BUILD}"

  # Prompt for build version selection during update
  BUILD_VERSION=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "Build Version" \
    --menu "Select Project Zomboid Build Version:" 12 60 2 \
    "41" "Build 41 (Stable)" \
    "42" "Build 42 (Beta/Unstable)" \
    3>&1 1>&2 2>&3)

  if [[ -z "$BUILD_VERSION" ]]; then
    msg_error "No build version selected. Update cancelled."
    exit
  fi

  # Warn if switching between builds
  if [[ "$CURRENT_BUILD" != "unknown" && "$CURRENT_BUILD" != "$BUILD_VERSION" ]]; then
    if ! whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "WARNING - Build Change" \
      --yesno "You are switching from Build ${CURRENT_BUILD} to Build ${BUILD_VERSION}.\n\nThis is NOT save-compatible! Existing saves will not work with the new build.\n\nDo you want to continue?" 14 65; then
      msg_error "Update cancelled."
      exit
    fi
  fi

  msg_info "Stopping Project Zomboid Server"
  systemctl stop project-zomboid-screen 2>/dev/null || true
  sleep 3
  msg_ok "Stopped Project Zomboid Server"

  msg_info "Updating Project Zomboid Server (Build ${BUILD_VERSION})"

  if [[ "$BUILD_VERSION" == "42" ]]; then
    su - pzserver -c "/usr/games/steamcmd +force_install_dir /opt/pzserver +login anonymous +app_update 380870 -beta unstable validate +quit" &>/dev/null
  else
    su - pzserver -c "/usr/games/steamcmd +force_install_dir /opt/pzserver +login anonymous +app_update 380870 validate +quit" &>/dev/null
  fi

  # Store version for reference
  echo "$BUILD_VERSION" > /opt/pzserver/.pz_build_version
  chown pzserver:pzserver /opt/pzserver/.pz_build_version

  msg_ok "Updated Project Zomboid Server to Build ${BUILD_VERSION}"

  msg_info "Starting Project Zomboid Server"
  systemctl start project-zomboid-screen
  msg_ok "Started Project Zomboid Server"

  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access the server on ports:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}UDP 16261${CL} ${YW}(Game Port 1)${CL}"
echo -e "${TAB}${GATEWAY}${BGN}UDP 16262${CL} ${YW}(Game Port 2)${CL}"
echo -e "${TAB}${GATEWAY}${BGN}TCP 27015${CL} ${YW}(RCON - Optional)${CL}"
echo -e "${INFO}${YW} First-run setup: Run /opt/pzserver/setup-admin.sh to set admin password${CL}"
echo -e "${INFO}${YW} Server config: /home/pzserver/Zomboid/Server/servertest.ini${CL}"
echo -e "${INFO}${YW} Console access: screen -r pzserver (detach: Ctrl+A, D)${CL}"
echo -e "${INFO}${YW} Build version: cat /opt/pzserver/.pz_build_version${CL}"
