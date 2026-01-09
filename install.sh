#!/bin/bash
# HostArchy Installation Script
# Interactive installer that transforms Arch Linux into a custom web hosting environment
# "The Perfect Edition"

set -uo pipefail

# ------------------------------------------------------------------
# Global Constants & Variables
# ------------------------------------------------------------------

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Directories
HOSTARCHY_DIR="/usr/local/hostarchy"
HOSTARCHY_ETC="/etc/hostarchy"
LOGFILE="/var/log/hostarchy-install.log"
VERSION="1.3-perfect"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# State
PROFILE="hosting"
YES=false
COMPAT_MODE=false
declare -A INSTALLED_COMPONENTS

# ------------------------------------------------------------------
# Core Infrastructure Functions
# ------------------------------------------------------------------

setup_logging() {
    mkdir -p "$(dirname "$LOGFILE")"
    # Create a fresh log file with permissions
    touch "$LOGFILE"
    chmod 600 "$LOGFILE"
    echo "--- HostArchy Installation Log Started $(date) ---" > "$LOGFILE"
    
    # Redirect stdout/stderr to log, keeping stdout on screen (fd 3)
    exec 3>&1
    exec > >(tee -a "$LOGFILE") 2>&1
}

cleanup_on_error() {
    local exit_code=$?
    local line_no=$1
    if [ $exit_code -ne 0 ]; then
        echo -e "\n${RED}[FATAL ERROR] Script failed at line $line_no with exit code $exit_code${NC}" >&3
        echo -e "${RED}Check $LOGFILE for details.${NC}" >&3
    fi
}
trap 'cleanup_on_error $LINENO' EXIT

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "\n${BLUE}==>${NC} ${1}"; }

prompt_yes_no() {
    local question="$1"
    local default="$2"
    local retval
    
    if [ "$YES" = true ]; then
        [[ "$default" =~ ^[Yy]$ ]] && return 0 || return 1
    fi

    local suffix
    if [[ "$default" =~ ^[Yy]$ ]]; then suffix="[Y/n]"; else suffix="[y/N]"; fi

    while true; do
        echo -ne "${CYAN}? $question $suffix: ${NC}" >&3
        read -r retval <&3
        
        if [ -z "$retval" ]; then retval="$default"; fi

        case "$retval" in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            * ) echo "Please answer yes or no." >&3 ;;
        esac
    done
}

prompt_string() {
    local question="$1"
    local default="$2"
    local input

    if [ "$YES" = true ]; then
        echo "$default"
        return
    fi

    echo -ne "${CYAN}? $question [$default]: ${NC}" >&3
    read -r input <&3
    echo "${input:-$default}"
}

check_dependencies() {
    local missing=()
    for cmd in ping cp ln mkdir pacman systemctl mountpoint id useradd; do
        if ! command -v "$cmd" >/dev/null 2>&1; then missing+=("$cmd"); fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing commands: ${missing[*]}${NC}" >&3
        exit 1
    fi
}

# ------------------------------------------------------------------
# Advanced Package Handling
# ------------------------------------------------------------------

update_keyring() {
    log_step "Updating Arch Linux Keyring..."
    # Ensure keys are valid before starting massive downloads
    if ! pacman -Sy --noconfirm archlinux-keyring; then
        log_warn "Failed to update keyring. Attempting to proceed, but package errors may occur."
    fi
}

install_packages() {
    local pkg_list=("$@")
    if [ ${#pkg_list[@]} -eq 0 ]; then return; fi

    log_step "Installing packages: ${pkg_list[*]}"
    
    # Try installation
    if pacman -S --needed --noconfirm "${pkg_list[@]}"; then
        echo -e "${GREEN}✓ Packages installed successfully.${NC}"
    else
        echo -e "${RED}Package installation failed.${NC}" >&3
        if prompt_yes_no "Retry installation with forced database refresh?" "y"; then
            pacman -Syyu --noconfirm "${pkg_list[@]}" || return 1
        else
            return 1
        fi
    fi
    return 0
}

# ------------------------------------------------------------------
# Configuration Logic ("The Thingies")
# ------------------------------------------------------------------

configure_mariadb() {
    log_step "Configuring MariaDB..."
    
    local datadir="/var/lib/mysql"
    if [ "$COMPAT_MODE" = false ]; then
        # If strict mode, we might want to override datadir, but standard Arch uses /var/lib/mysql.
        # We will symlink or bind mount logic in create_data_dir, 
        # but here we ensure the DB is initialized.
        : # Logic handled by layout
    fi

    if [ ! -d "$datadir/mysql" ]; then
        echo "Initializing database data directory..."
        mariadb-install-db --user=mysql --basedir=/usr --datadir="$datadir"
    fi

    systemctl enable mariadb
    systemctl start mariadb

    # Wait for startup
    local i=0
    while ! systemctl is-active mariadb >/dev/null; do
        sleep 1
        ((i++))
        if [ $i -gt 10 ]; then log_warn "MariaDB is taking a long time to start..."; break; fi
    done

    if systemctl is-active mariadb >/dev/null; then
        echo -e "${GREEN}✓ MariaDB is running.${NC}"
        # Secure installation automation could go here
    else
        echo -e "${RED}✗ MariaDB failed to start. Check 'journalctl -xeu mariadb'${NC}"
    fi
}

configure_postgresql() {
    log_step "Configuring PostgreSQL..."
    local datadir="/var/lib/postgres/data"
    
    # Switch to postgres user to check/init db
    if ! su - postgres -c "[ -d '$datadir' ] && [ -f '$datadir/PG_VERSION' ]"; then
        echo "Initializing PostgreSQL cluster..."
        su - postgres -c "initdb -D '$datadir' --locale=C.UTF-8"
    fi

    systemctl enable postgresql
    systemctl start postgresql
    
    if systemctl is-active postgresql >/dev/null; then
        echo -e "${GREEN}✓ PostgreSQL is running.${NC}"
    else
        echo -e "${RED}✗ PostgreSQL failed to start.${NC}"
    fi
}

configure_nginx_php() {
    log_step "Configuring Web Stack (Nginx + PHP)..."
    
    # PHP Configuration
    if [[ " ${INSTALLED_COMPONENTS[@]} " =~ " php-fpm " ]]; then
        # Ensure php-fpm is ready
        systemctl enable php-fpm
        systemctl start php-fpm
    fi

    # Nginx Configuration
    # Test config before starting
    if nginx -t; then
        systemctl enable nginx
        systemctl start nginx
        echo -e "${GREEN}✓ Nginx started successfully.${NC}"
    else
        echo -e "${RED}✗ Nginx configuration test failed. Service not started.${NC}"
    fi
}

configure_firewall() {
    log_step "Configuring Firewall (UFW)..."
    
    # Reset to defaults to ensure clean slate
    ufw --force reset >/dev/null
    
    # Basic Policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Essential Rules
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Enable
    ufw --force enable
    
    echo -e "${GREEN}✓ Firewall active with SSH/HTTP/HTTPS allowed.${NC}"
}

# ------------------------------------------------------------------
# Main Logic
# ------------------------------------------------------------------

setup_logging

echo -e "${BLUE}
  _   _           _      _              _           
 | | | | ___  ___| |_   / \   _ __ ___ | |__  _   _ 
 | |_| |/ _ \/ __| __| / _ \ | '__/ __|| '_ \| | | |
 |  _  | (_) \__ \ |_ / ___ \| | | (__ | | | | |_| |
 |_| |_|\___/|___/\__/_/   \_\_|  \___||_| |_|\__, |
                                              |___/ 
 HostArchy Installer v${VERSION}
${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Run as root.${NC}" >&3
    exit 1
fi

check_dependencies

# --- System Setup ---

echo -e "\n${YELLOW}--- System Configuration ---${NC}"

# Hostname
CURRENT_HOSTNAME=$(cat /etc/hostname 2>/dev/null || echo "localhost")
NEW_HOSTNAME=$(prompt_string "System Hostname" "$CURRENT_HOSTNAME")
if [ "$NEW_HOSTNAME" != "$CURRENT_HOSTNAME" ]; then
    hostnamectl set-hostname "$NEW_HOSTNAME"
    # Update /etc/hosts
    if grep -q "127.0.1.1" /etc/hosts; then
        sed -i "s/127.0.1.1.*/127.0.1.1\t$NEW_HOSTNAME/g" /etc/hosts
    else
        echo -e "127.0.1.1\t$NEW_HOSTNAME" >> /etc/hosts
    fi
    echo -e "${GREEN}✓ Hostname set to $NEW_HOSTNAME${NC}"
fi

# Timezone
CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
NEW_TZ=$(prompt_string "System Timezone" "$CURRENT_TZ")
if [ "$NEW_TZ" != "$CURRENT_TZ" ]; then
    if timedatectl set-timezone "$NEW_TZ" 2>/dev/null; then
        echo -e "${GREEN}✓ Timezone set to $NEW_TZ${NC}"
    else
        log_warn "Could not set timezone. Check manually."
    fi
fi

# Admin User
echo ""
if prompt_yes_no "Create a dedicated sudo admin user?" "y"; then
    ADMIN_USER=$(prompt_string "Username" "admin")
    if ! id "$ADMIN_USER" &>/dev/null; then
        useradd -m -G wheel -s /bin/bash "$ADMIN_USER"
        echo -e "${YELLOW}Set password for $ADMIN_USER:${NC}" >&3
        passwd "$ADMIN_USER"
        
        # Safer sudo configuration using .d directory
        if [ -d /etc/sudoers.d ]; then
            echo "%wheel ALL=(ALL:ALL) ALL" > "/etc/sudoers.d/10-hostarchy-wheel"
            chmod 440 "/etc/sudoers.d/10-hostarchy-wheel"
            echo -e "${GREEN}✓ Sudo privileges granted via /etc/sudoers.d/${NC}"
        else
            # Fallback
            sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
        fi
    else
        echo -e "${YELLOW}⚠ User $ADMIN_USER already exists${NC}"
    fi
fi

# Storage Layout
echo -e "\n${YELLOW}--- Storage Configuration ---${NC}"
if mountpoint -q /db 2>/dev/null; then
    echo -e "${GREEN}✓ /db mount detected (Strict Mode)${NC}"
    COMPAT_MODE=false
else
    if prompt_yes_no "Use Compatibility Mode (store data in /var)?" "y"; then
        COMPAT_MODE=true
    else
        echo -e "${RED}Aborted. Mount /db or accept compatibility.${NC}" >&3
        exit 1
    fi
fi

# --- Package Selection ---

echo -e "\n${YELLOW}--- Software Selection ---${NC}"

PACKAGES=(base-devel git openssh htop rsync curl wget vim man-db unzip)
TO_CONFIGURE=()

if prompt_yes_no "Install Nginx Web Server?" "y"; then
    PACKAGES+=(nginx)
    TO_CONFIGURE+=(nginx)
fi

if prompt_yes_no "Install PHP & FPM?" "y"; then
    PACKAGES+=(php php-fpm php-opcache php-gd php-intl php-mbstring)
    TO_CONFIGURE+=(php)
fi

if prompt_yes_no "Install MariaDB Database?" "y"; then
    PACKAGES+=(mariadb mariadb-clients)
    TO_CONFIGURE+=(mariadb)
fi

if prompt_yes_no "Install PostgreSQL?" "n"; then
    PACKAGES+=(postgresql postgresql-libs)
    TO_CONFIGURE+=(postgres)
fi

if prompt_yes_no "Install Redis Cache?" "n"; then
    PACKAGES+=(redis)
    TO_CONFIGURE+=(redis)
fi

if prompt_yes_no "Install Firewall (UFW) & Fail2Ban?" "y"; then
    PACKAGES+=(ufw fail2ban)
    TO_CONFIGURE+=(security)
fi

if prompt_yes_no "Install System Monitors (btop)?" "y"; then
    PACKAGES+=(btop)
fi

# Kernel Check - Don't reinstall kernel if running on it, prevents version mismatch until reboot
if [[ "$PROFILE" == "performance" ]]; then
    if prompt_yes_no "Install Zen Kernel (Requires Reboot)?" "n"; then
        PACKAGES+=(linux-zen linux-zen-headers)
    fi
fi

# --- Installation Execution ---

echo -e "\n${YELLOW}--- Installation Phase ---${NC}"
echo "Packages: ${PACKAGES[*]}"
if ! prompt_yes_no "Proceed?" "y"; then echo "Aborted."; exit 0; fi

# Update Keys first
update_keyring

# Install
if install_packages "${PACKAGES[@]}"; then
    # Record installed components for config logic
    for pkg in "${PACKAGES[@]}"; do INSTALLED_COMPONENTS["$pkg"]=1; done
else
    echo -e "${RED}Critical failure during package installation.${NC}" >&3
    exit 1
fi

# --- Filesystem Setup ---

echo -e "${YELLOW}Setting up HostArchy directories...${NC}"
mkdir -p "$HOSTARCHY_DIR"/{bin,lib,templates}
mkdir -p "$HOSTARCHY_ETC"/{config,profiles,state,hooks}

setup_data_dir() {
    local target="$1"
    local compat_target="$2"
    
    if [ "$COMPAT_MODE" = true ]; then
        mkdir -p "$compat_target"
        if [ ! -d "$target" ]; then ln -sf "$compat_target" "$target"; fi
    else
        mkdir -p "$target"
    fi
}

setup_data_dir "/srv/http" "/var/lib/hostarchy/http"
setup_data_dir "/var/lib/mysql" "/var/lib/hostarchy/mysql"
setup_data_dir "/var/lib/postgres" "/var/lib/hostarchy/postgres"

# --- Configuration Execution ---

echo -e "\n${YELLOW}--- Configuration Phase ---${NC}"

# 1. Database
if [[ " ${TO_CONFIGURE[@]} " =~ " mariadb " ]]; then
    configure_mariadb
fi

if [[ " ${TO_CONFIGURE[@]} " =~ " postgres " ]]; then
    configure_postgresql
fi

if [[ " ${TO_CONFIGURE[@]} " =~ " redis " ]]; then
    log_step "Enabling Redis..."
    systemctl enable --now redis
fi

# 2. Web Stack
if [[ " ${TO_CONFIGURE[@]} " =~ " nginx " ]] || [[ " ${TO_CONFIGURE[@]} " =~ " php " ]]; then
    configure_nginx_php
fi

# 3. Security
if [[ " ${TO_CONFIGURE[@]} " =~ " security " ]]; then
    configure_firewall
    systemctl enable --now fail2ban
    echo -e "${GREEN}✓ Fail2Ban active.${NC}"
fi

# --- Finalization ---

echo -e "${YELLOW}Finalizing state...${NC}"
{
    echo "PROFILE=$PROFILE"
    echo "INSTALLED_DATE=$(date -Iseconds)"
    echo "COMPAT_MODE=$COMPAT_MODE"
    echo "VERSION=$VERSION"
    echo "INSTALLED_PACKAGES=\"${PACKAGES[*]}\""
} > "$HOSTARCHY_ETC/state/installed"

# Copy internal scripts if they exist (handling the external source requirement gracefully)
if [ -d "$SCRIPT_DIR/bin" ]; then
    cp -rn "$SCRIPT_DIR/bin/"* "$HOSTARCHY_DIR/bin/" 2>/dev/null || true
fi

echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}   HostArchy Installation Complete!   ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e " Log File : $LOGFILE"
echo -e " Hostname : $NEW_HOSTNAME"
echo -e " Storage  : $([ "$COMPAT_MODE" = true ] && echo 'Compatibility (/var)' || echo 'Strict (/db)')"
echo -e "\n${CYAN}Action Required:${NC} Re-login or reboot to apply group changes (sudo/docker)."