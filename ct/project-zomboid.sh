#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: mbarber107
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://projectzomboid.com/

# Standalone mode detection - if FUNCTIONS_FILE_PATH is not set, run standalone
if [[ -z "$FUNCTIONS_FILE_PATH" ]]; then
  # ============== STANDALONE MODE ==============
  set -euo pipefail

  # Colors
  RD='\033[0;31m'
  GN='\033[0;32m'
  YW='\033[0;33m'
  BL='\033[0;34m'
  CL='\033[0m'

  # Helper functions
  msg_info() { echo -e "${BL}[INFO]${CL} $1"; }
  msg_ok() { echo -e "${GN}[OK]${CL} $1"; }
  msg_error() { echo -e "${RD}[ERROR]${CL} $1"; }
  msg_warn() { echo -e "${YW}[WARN]${CL} $1"; }

  # Check if running on Proxmox
  if ! command -v pveversion &>/dev/null; then
    msg_error "This script must be run on a Proxmox VE host"
    exit 1
  fi

  # Check if running as root
  if [[ $EUID -ne 0 ]]; then
    msg_error "This script must be run as root"
    exit 1
  fi

  APP="Project-Zomboid"
  var_cpu="${var_cpu:-2}"
  var_ram="${var_ram:-4096}"
  var_disk="${var_disk:-10}"
  var_os="${var_os:-debian}"
  var_version="${var_version:-12}"
  var_unprivileged="${var_unprivileged:-1}"

  echo -e "${GN}"
  echo "  ____            _           _     _____                 _     _     _ "
  echo " |  _ \ _ __ ___ (_) ___  ___| |_  |__  /___  _ __ ___   | |__ (_) __| |"
  echo " | |_) | '__/ _ \| |/ _ \/ __| __|   / // _ \| '_ \` _ \  | '_ \| |/ _\` |"
  echo " |  __/| | | (_) | |  __/ (__| |_   / /| (_) | | | | | | | |_) | | (_| |"
  echo " |_|   |_|  \___// |\___|\___|\__| /____\___/|_| |_| |_| |_.__/|_|\__,_|"
  echo "               |__/                                                     "
  echo -e "${CL}"
  echo "Proxmox VE Project Zomboid Server LXC Creator"
  echo ""

  # Get next available CT ID
  CTID=$(pvesh get /cluster/nextid)
  msg_info "Next available CT ID: ${CTID}"

  # Check if running interactively
  if [[ -t 0 ]]; then
    INTERACTIVE=true
  else
    INTERACTIVE=false
    msg_warn "Non-interactive mode: using defaults"
  fi

  # Select storage
  STORAGE="${PZ_STORAGE:-}"
  if [[ -z "$STORAGE" ]]; then
    if [[ "$INTERACTIVE" == "true" ]]; then
      echo ""
      msg_info "Available storage pools:"
      pvesm status -content rootdir | awk 'NR>1 {print "  " $1 " (" $4 " available)"}'
      echo ""
      read -p "Enter storage pool name [local-lvm]: " STORAGE
    fi
    STORAGE=${STORAGE:-local-lvm}
  fi

  # Validate storage
  if ! pvesm status -storage "$STORAGE" &>/dev/null; then
    msg_error "Storage '$STORAGE' not found"
    exit 1
  fi

  # Get container template - find available Debian 12 template
  msg_info "Finding Debian 12 template..."

  # Update template list
  pveam update &>/dev/null || true

  # Find a Debian 12 template
  TEMPLATE=$(pveam available -section system | grep -E "debian-12.*amd64" | head -1 | awk '{print $2}')

  if [[ -z "$TEMPLATE" ]]; then
    msg_error "No Debian 12 template found. Please run: pveam update"
    exit 1
  fi

  TEMPLATE_PATH="/var/lib/vz/template/cache/${TEMPLATE}"

  if [[ ! -f "$TEMPLATE_PATH" ]]; then
    msg_info "Downloading template: ${TEMPLATE}"
    pveam download local "$TEMPLATE"
  fi
  msg_ok "Template ready: ${TEMPLATE}"

  # Network configuration
  NET_CONFIG="${PZ_NET_CONFIG:-}"
  if [[ -z "$NET_CONFIG" ]]; then
    if [[ "$INTERACTIVE" == "true" ]]; then
      echo ""
      read -p "Use DHCP for network? [Y/n]: " USE_DHCP
      USE_DHCP=${USE_DHCP:-Y}

      if [[ "${USE_DHCP,,}" == "y" ]]; then
        NET_CONFIG="name=eth0,bridge=vmbr0,ip=dhcp"
      else
        read -p "Enter IP address (e.g., 192.168.1.100/24): " IP_ADDR
        read -p "Enter gateway: " GATEWAY
        NET_CONFIG="name=eth0,bridge=vmbr0,ip=${IP_ADDR},gw=${GATEWAY}"
      fi
    else
      NET_CONFIG="name=eth0,bridge=vmbr0,ip=dhcp"
    fi
  fi

  # Build selection
  BUILD_VERSION="${PZ_BUILD_VERSION:-}"
  if [[ -z "$BUILD_VERSION" ]]; then
    if [[ "$INTERACTIVE" == "true" ]]; then
      echo ""
      echo "Select Project Zomboid Build Version:"
      echo "  1) Build 41 (Stable - Recommended)"
      echo "  2) Build 42 (Beta/Unstable)"
      read -p "Enter choice [1]: " BUILD_CHOICE
      BUILD_CHOICE=${BUILD_CHOICE:-1}

      if [[ "$BUILD_CHOICE" == "2" ]]; then
        BUILD_VERSION="42"
      else
        BUILD_VERSION="41"
      fi
    else
      BUILD_VERSION="41"
    fi
  fi

  # Hostname
  HOSTNAME="project-zomboid"

  # Create container
  msg_info "Creating LXC container ${CTID}..."
  pct create "$CTID" "local:vztmpl/${TEMPLATE}" \
    --hostname "$HOSTNAME" \
    --memory "$var_ram" \
    --cores "$var_cpu" \
    --rootfs "${STORAGE}:${var_disk}" \
    --net0 "$NET_CONFIG" \
    --unprivileged "$var_unprivileged" \
    --features nesting=1 \
    --onboot 1 \
    --start 1

  msg_ok "Container ${CTID} created"

  # Wait for container to start
  msg_info "Waiting for container to start..."
  sleep 5

  # Wait for network
  msg_info "Waiting for network..."
  for i in {1..30}; do
    if pct exec "$CTID" -- ping -c 1 8.8.8.8 &>/dev/null; then
      break
    fi
    sleep 2
  done

  # Download and run install script
  msg_info "Running installation script inside container..."

  pct exec "$CTID" -- bash -c "
    export BUILD_VERSION='${BUILD_VERSION}'
    apt-get update
    apt-get install -y curl
    curl -sfSLH 'Accept: application/vnd.github.v3.raw' \
      'https://api.github.com/repos/mbarber107/pz-proxmox-hs/contents/install/project-zomboid-install.sh' \
      -o /tmp/install.sh
    chmod +x /tmp/install.sh
    bash /tmp/install.sh
  "

  # Get container IP
  CT_IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')

  msg_ok "Installation complete!"
  echo ""
  echo -e "${GN}========================================${CL}"
  echo -e "${GN} Project Zomboid Server Ready!${CL}"
  echo -e "${GN}========================================${CL}"
  echo ""
  echo -e "Container ID: ${YW}${CTID}${CL}"
  echo -e "Container IP: ${YW}${CT_IP}${CL}"
  echo -e "Build Version: ${YW}${BUILD_VERSION}${CL}"
  echo ""
  echo "Access the server on ports:"
  echo -e "  ${GN}UDP 16261${CL} (Game Port 1)"
  echo -e "  ${GN}UDP 16262${CL} (Game Port 2)"
  echo -e "  ${GN}TCP 27015${CL} (RCON - Optional)"
  echo ""
  echo "Next steps:"
  echo -e "  1. Enter container: ${YW}pct enter ${CTID}${CL}"
  echo -e "  2. Set admin password: ${YW}/opt/pzserver/setup-admin.sh${CL}"
  echo -e "  3. Start server: ${YW}systemctl start project-zomboid-screen${CL}"
  echo ""
  echo -e "Server config: ${YW}/home/pzserver/Zomboid/Server/servertest.ini${CL}"
  echo -e "Console access: ${YW}screen -r pzserver${CL} (Ctrl+A, D to detach)"
  echo ""

  exit 0
fi

# ============== COMMUNITY-SCRIPTS MODE ==============
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
