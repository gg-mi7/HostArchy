#!/bin/bash
# HostArchy Installation Script
# Idempotent installer that transforms Arch Linux into a web hosting environment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# HostArchy installation directory
HOSTARCHY_DIR="/usr/local/hostarchy"
HOSTARCHY_ETC="/etc/hostarchy"

# Default profile
PROFILE="hosting"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile=*)
            PROFILE="${1#*=}"
            shift
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Validate profile
case $PROFILE in
    hosting|performance|database)
        echo -e "${GREEN}Selected profile: $PROFILE${NC}"
        ;;
    *)
        echo -e "${RED}Invalid profile: $PROFILE${NC}"
        echo "Valid profiles: hosting, performance, database"
        exit 1
        ;;
esac

# Pre-flight checks
echo -e "${YELLOW}Running pre-flight checks...${NC}"

# Check if running on Arch Linux
if [ ! -f /etc/arch-release ]; then
    echo -e "${RED}Error: This script must be run on Arch Linux${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Arch Linux detected${NC}"

# Check if /db mount exists or if we're in compatibility mode
if mountpoint -q /db 2>/dev/null; then
    echo -e "${GREEN}✓ /db mount detected (Strict Mode)${NC}"
    COMPAT_MODE=false
elif [ "$PROFILE" = "performance" ] || [ "$PROFILE" = "database" ]; then
    echo -e "${RED}Error: /db mount required for $PROFILE profile${NC}"
    exit 1
else
    echo -e "${YELLOW}⚠ /db mount not detected (Compatibility Mode)${NC}"
    read -p "Continue without physical isolation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    COMPAT_MODE=true
fi

# Check internet connectivity
if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo -e "${RED}Error: No internet connectivity detected${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Internet connectivity confirmed${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root${NC}"
    exit 1
fi

# Create HostArchy directories
echo -e "${YELLOW}Creating directory structure...${NC}"
mkdir -p "$HOSTARCHY_DIR"/{bin,lib,templates}
mkdir -p "$HOSTARCHY_ETC"/{config,profiles,state,hooks}

# Create data directories
if [ "$COMPAT_MODE" = false ] || mountpoint -q /srv 2>/dev/null; then
    mkdir -p /srv/{http,git,backups}
else
    mkdir -p /var/lib/hostarchy/srv/{http,git,backups}
    if [ ! -d /srv ]; then
        ln -sf /var/lib/hostarchy/srv /srv
    fi
fi

if [ "$COMPAT_MODE" = false ] || mountpoint -q /db 2>/dev/null; then
    mkdir -p /db/{mariadb,postgres,redis,metadata}
else
    mkdir -p /var/lib/hostarchy/db/{mariadb,postgres,redis,metadata}
    if [ ! -d /db ]; then
        ln -sf /var/lib/hostarchy/db /db
    fi
fi
echo -e "${GREEN}✓ Directory structure created${NC}"

# Copy files to installation directory
echo -e "${YELLOW}Installing HostArchy files...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy binaries
if [ -f "$SCRIPT_DIR/bin/hostarchy" ]; then
    cp "$SCRIPT_DIR/bin/hostarchy" "$HOSTARCHY_DIR/bin/"
    chmod +x "$HOSTARCHY_DIR/bin/hostarchy"
fi

# Copy libraries
if [ -d "$SCRIPT_DIR/lib" ]; then
    cp -r "$SCRIPT_DIR/lib"/* "$HOSTARCHY_DIR/lib/" 2>/dev/null || true
    chmod +x "$HOSTARCHY_DIR/lib"/*.sh 2>/dev/null || true
fi

# Copy templates
if [ -d "$SCRIPT_DIR/templates" ]; then
    cp -r "$SCRIPT_DIR/templates"/* "$HOSTARCHY_DIR/templates/" 2>/dev/null || true
fi

# Copy profiles
if [ -d "$SCRIPT_DIR/profiles" ]; then
    mkdir -p "$HOSTARCHY_DIR/profiles"
    cp -r "$SCRIPT_DIR/profiles"/* "$HOSTARCHY_DIR/profiles/" 2>/dev/null || true
    chmod +x "$HOSTARCHY_DIR/profiles"/*.sh 2>/dev/null || true
fi

# Symlink hostarchy binary to /usr/local/bin
if [ ! -L /usr/local/bin/hostarchy ]; then
    ln -s "$HOSTARCHY_DIR/bin/hostarchy" /usr/local/bin/hostarchy
    echo -e "${GREEN}✓ HostArchy CLI installed${NC}"
fi

# Install required packages based on profile
echo -e "${YELLOW}Installing packages for profile: $PROFILE${NC}"

# Base packages (already installed, but verify)
pacman -Sy --noconfirm --needed \
    base linux linux-firmware systemd-sysvcompat \
    git base-devel openssh neovim htop rsync \
    nginx php php-fpm php-opcache \
    mariadb postgresql redis fail2ban nftables

# Install profile-specific packages
case $PROFILE in
    performance|database)
        # Additional performance packages
        pacman -Sy --noconfirm --needed btrfs-progs xfsprogs
        ;;
esac

echo -e "${GREEN}✓ Packages installed${NC}"

# Apply profile configuration
echo -e "${YELLOW}Applying profile: $PROFILE${NC}"
# Source from installed location or script directory
if [ -f "$HOSTARCHY_DIR/profiles/$PROFILE.sh" ]; then
    source "$HOSTARCHY_DIR/profiles/$PROFILE.sh"
    apply_profile
elif [ -f "$SCRIPT_DIR/profiles/$PROFILE.sh" ]; then
    source "$SCRIPT_DIR/profiles/$PROFILE.sh"
    apply_profile
else
    echo -e "${YELLOW}⚠ Profile script not found, using defaults${NC}"
fi

# Apply system tuning
echo -e "${YELLOW}Applying system tuning...${NC}"
# Source from installed location or script directory
if [ -f "$HOSTARCHY_DIR/lib/system-tuning.sh" ]; then
    source "$HOSTARCHY_DIR/lib/system-tuning.sh"
    apply_system_tuning
elif [ -f "$SCRIPT_DIR/lib/system-tuning.sh" ]; then
    source "$SCRIPT_DIR/lib/system-tuning.sh"
    apply_system_tuning
fi

# Configure services
echo -e "${YELLOW}Configuring services...${NC}"
# Source from installed location or script directory
if [ -f "$HOSTARCHY_DIR/lib/service-config.sh" ]; then
    source "$HOSTARCHY_DIR/lib/service-config.sh"
    configure_services "$PROFILE"
elif [ -f "$SCRIPT_DIR/lib/service-config.sh" ]; then
    source "$SCRIPT_DIR/lib/service-config.sh"
    configure_services "$PROFILE"
fi

# Install pacman hook
echo -e "${YELLOW}Installing pacman hook...${NC}"
mkdir -p /etc/pacman.d/hooks
if [ -f "$SCRIPT_DIR/pacman-hooks/hostarchy.hook" ]; then
    cp "$SCRIPT_DIR/pacman-hooks/hostarchy.hook" /etc/pacman.d/hooks/
    chmod 644 /etc/pacman.d/hooks/hostarchy.hook
    echo -e "${GREEN}✓ Pacman hook installed${NC}"
fi

# Save current state
echo -e "${YELLOW}Saving installation state...${NC}"
cat > "$HOSTARCHY_ETC/state/installed" <<EOF
PROFILE=$PROFILE
INSTALLED_DATE=$(date -Iseconds)
COMPAT_MODE=$COMPAT_MODE
VERSION=1.1
EOF

echo -e "${GREEN}✓ HostArchy installation completed successfully!${NC}"
echo -e "${GREEN}Profile: $PROFILE${NC}"
echo -e "${GREEN}Run 'hostarchy status' to verify installation${NC}"

