#!/bin/bash
# HostArchy Installation Script
# Interactive installer that transforms Arch Linux into a custom web hosting environment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# HostArchy installation directory
HOSTARCHY_DIR="/usr/local/hostarchy"
HOSTARCHY_ETC="/etc/hostarchy"
LOGFILE="/var/log/hostarchy-install.log"
VERSION="1.2-interactive"

# Default state variables
PROFILE="hosting"
YES=false
COMPAT_MODE=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------

setup_logging() {
    mkdir -p "$(dirname "$LOGFILE")"
    # redirect stdout and stderr to logfile, but keep showing them on screen
    exec > >(tee -a "$LOGFILE") 2>&1
}

# Prompt user for Yes/No input
# Usage: prompt_yes_no "Question?" "default (y/n)"
prompt_yes_no() {
    local question="$1"
    local default="$2"
    local retval
    
    if [ "$YES" = true ]; then
        # Return true (0) if default is y, false (1) if n
        [[ "$default" =~ ^[Yy]$ ]] && return 0 || return 1
    fi

    local suffix
    if [[ "$default" =~ ^[Yy]$ ]]; then suffix="[Y/n]"; else suffix="[y/N]"; fi

    while true; do
        echo -ne "${CYAN}? $question $suffix: ${NC}"
        read -r retval
        
        # Handle empty input (default)
        if [ -z "$retval" ]; then
            retval="$default"
        fi

        case "$retval" in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            * ) echo "Please answer yes or no." ;;
        esac
    done
}

# Prompt for string input
# Usage: prompt_string "Question?" "default_value"
prompt_string() {
    local question="$1"
    local default="$2"
    local input

    if [ "$YES" = true ]; then
        echo "$default"
        return
    fi

    echo -ne "${CYAN}? $question [$default]: ${NC}"
    read -r input
    echo "${input:-$default}"
}

check_dependencies() {
    local missing=()
    for cmd in ping cp ln mkdir pacman systemctl mountpoint; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required commands: ${missing[*]}${NC}"
        exit 1
    fi
}

safe_source() {
    local file="$1"
    if [ -f "$HOSTARCHY_DIR/$file" ]; then
        source "$HOSTARCHY_DIR/$file"
        return 0
    elif [ -f "$SCRIPT_DIR/$file" ]; then
        source "$SCRIPT_DIR/$file"
        return 0
    else
        echo -e "${YELLOW}⚠ Skipped: $file not found${NC}"
        return 1
    fi
}

create_data_dir() {
    local target="$1"
    shift
    local fallback="$1"
    shift
    
    if [ "$COMPAT_MODE" = false ] || mountpoint -q "$target" 2>/dev/null; then
        for dir in "$@"; do mkdir -p "$target/$dir"; done
    else
        for dir in "$@"; do mkdir -p "$fallback/$dir"; done
        [ ! -d "$target" ] && ln -sf "$fallback" "$target"
    fi
}

# ------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile=*) PROFILE="${1#*=}"; shift ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --yes|-y) YES=true; shift ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
    esac
done

setup_logging

echo -e "${BLUE}HostArchy Interactive Installer v${VERSION}${NC}"
echo "=================================================="
echo "Log: $LOGFILE"

# Root check
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Run as root.${NC}"; exit 1
fi

check_dependencies

echo -e "\n${YELLOW}--- System Configuration ---${NC}"

# 1. Hostname Configuration
CURRENT_HOSTNAME=$(cat /etc/hostname)
NEW_HOSTNAME=$(prompt_string "System Hostname" "$CURRENT_HOSTNAME")
if [ "$NEW_HOSTNAME" != "$CURRENT_HOSTNAME" ]; then
    hostnamectl set-hostname "$NEW_HOSTNAME"
    echo -e "${GREEN}✓ Hostname set to $NEW_HOSTNAME${NC}"
fi

# 2. Timezone
CURRENT_TZ=$(timedatectl show --property=Timezone --value)
NEW_TZ=$(prompt_string "System Timezone" "${CURRENT_TZ:-UTC}")
if [ "$NEW_TZ" != "$CURRENT_TZ" ]; then
    if timedatectl set-timezone "$NEW_TZ" 2>/dev/null; then
        echo -e "${GREEN}✓ Timezone set to $NEW_TZ${NC}"
    else
        echo -e "${RED}⚠ Invalid timezone, skipping.${NC}"
    fi
fi

# 3. Create Admin User
echo ""
if prompt_yes_no "Create a dedicated sudo admin user?" "y"; then
    ADMIN_USER=$(prompt_string "Username" "admin")
    if ! id "$ADMIN_USER" &>/dev/null; then
        useradd -m -G wheel -s /bin/bash "$ADMIN_USER"
        echo -e "${YELLOW}Please enter password for $ADMIN_USER:${NC}"
        passwd "$ADMIN_USER"
        # Ensure wheel group has sudo access
        if [ -f /etc/sudoers ]; then
            sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
        fi
        echo -e "${GREEN}✓ User $ADMIN_USER created${NC}"
    else
        echo -e "${YELLOW}⚠ User $ADMIN_USER already exists${NC}"
    fi
fi

echo -e "\n${YELLOW}--- Storage Configuration ---${NC}"

# 4. Storage / Compatibility Mode
if mountpoint -q /db 2>/dev/null; then
    echo -e "${GREEN}✓ /db mount detected (Strict Mode)${NC}"
    COMPAT_MODE=false
else
    echo -e "${YELLOW}/db mount not found.${NC}"
    if prompt_yes_no "Use Compatibility Mode (store data in /var)?" "y"; then
        COMPAT_MODE=true
    else
        echo -e "${RED}Installation aborted. Please mount /db or accept compatibility mode.${NC}"
        exit 1
    fi
fi

echo -e "\n${YELLOW}--- Package Selection ---${NC}"

# Base packages that are always installed
PACKAGES=(base linux linux-firmware systemd-sysvcompat git base-devel openssh htop rsync curl wget)

# Interactive Package Selection
if prompt_yes_no "Install Nginx Web Server?" "y"; then
    PACKAGES+=(nginx)
fi

if prompt_yes_no "Install PHP & FPM?" "y"; then
    PACKAGES+=(php php-fpm php-opcache php-gd php-intl)
fi

if prompt_yes_no "Install MariaDB Database?" "y"; then
    PACKAGES+=(mariadb mariadb-clients)
fi

if prompt_yes_no "Install PostgreSQL?" "n"; then
    PACKAGES+=(postgresql postgresql-libs)
fi

if prompt_yes_no "Install Redis Cache?" "n"; then
    PACKAGES+=(redis)
fi

if prompt_yes_no "Install Network Security (ufw + fail2ban)?" "y"; then
    PACKAGES+=(ufw fail2ban)
fi

if prompt_yes_no "Install System Monitors (btop)?" "y"; then
    PACKAGES+=(btop)
fi

# Profile specific additions
if [[ "$PROFILE" == "performance" ]]; then
    PACKAGES+=(linux-zen) # Use zen kernel for performance
fi

echo -e "\n${YELLOW}--- Installation ---${NC}"
echo "Packages to install: ${PACKAGES[*]}"

if ! prompt_yes_no "Proceed with installation?" "y"; then
    echo "Aborted by user."
    exit 0
fi

# Perform Installation
echo -e "${YELLOW}Installing packages...${NC}"
pacman -Sy --noconfirm --needed "${PACKAGES[@]}"

# Filesystem Setup
echo -e "${YELLOW}Setting up directories...${NC}"
mkdir -p "$HOSTARCHY_DIR"/{bin,lib,templates}
mkdir -p "$HOSTARCHY_ETC"/{config,profiles,state,hooks}

create_data_dir /srv /var/lib/hostarchy/srv http git backups
create_data_dir /db /var/lib/hostarchy/db mariadb postgres redis metadata

# Copy Files (Binaries/Libs)
echo -e "${YELLOW}Copying HostArchy core files...${NC}"
if [ -d "$SCRIPT_DIR/bin" ]; then
    cp -rn "$SCRIPT_DIR/bin"/* "$HOSTARCHY_DIR/bin/" 2>/dev/null || true
    chmod +x "$HOSTARCHY_DIR/bin/"* 2>/dev/null || true
    ln -sf "$HOSTARCHY_DIR/bin/hostarchy" /usr/local/bin/hostarchy
fi

# Copy Libraries & Templates
[ -d "$SCRIPT_DIR/lib" ] && cp -rn "$SCRIPT_DIR/lib"/* "$HOSTARCHY_DIR/lib/" 2>/dev/null || true
[ -d "$SCRIPT_DIR/templates" ] && cp -rn "$SCRIPT_DIR/templates"/* "$HOSTARCHY_DIR/templates/" 2>/dev/null || true
[ -d "$SCRIPT_DIR/profiles" ] && cp -rn "$SCRIPT_DIR/profiles"/* "$HOSTARCHY_DIR/profiles/" 2>/dev/null || true

# Apply Configurations
echo -e "${YELLOW}Applying configurations...${NC}"

if safe_source "profiles/$PROFILE.sh"; then
    echo -e "Running profile: $PROFILE"
    type apply_profile &>/dev/null && apply_profile
fi

safe_source "lib/system-tuning.sh" && apply_system_tuning
safe_source "lib/service-config.sh" && configure_services "$PROFILE"

# Final State Save
echo -e "${YELLOW}Finalizing...${NC}"
mkdir -p "$HOSTARCHY_ETC/state"
{
    echo "PROFILE=$PROFILE"
    echo "INSTALLED_DATE=$(date -Iseconds)"
    echo "COMPAT_MODE=$COMPAT_MODE"
    echo "VERSION=$VERSION"
    echo "INSTALLED_PACKAGES=\"${PACKAGES[*]}\""
} > "$HOSTARCHY_ETC/state/installed"

echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}  HostArchy Installation Complete!  ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e " Profile  : $PROFILE"
echo -e " Hostname : $NEW_HOSTNAME"
echo -e " Data Dir : $([ "$COMPAT_MODE" = true ] && echo '/var/lib/hostarchy' || echo '/db /srv')"
echo -e "\n Run 'hostarchy status' to verify services."