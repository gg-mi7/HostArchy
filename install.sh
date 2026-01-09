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
LOGFILE="/var/log/hostarchy-install.log"
VERSION="1.1"

# Default profile
PROFILE="hosting"
YES=false

# Setup logging
setup_logging() {
    mkdir -p "$(dirname "$LOGFILE")"
    exec > >(tee -a "$LOGFILE") 2>&1
}

# Check required commands exist
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

# Safe source function - tries multiple locations
safe_source() {
    local file="$1"
    local script_dir="${2:-$SCRIPT_DIR}"
    
    if [ -f "$HOSTARCHY_DIR/$file" ]; then
        source "$HOSTARCHY_DIR/$file"
        return 0
    elif [ -f "$script_dir/$file" ]; then
        source "$script_dir/$file"
        return 0
    else
        echo -e "${YELLOW}⚠ $file not found${NC}"
        return 1
    fi
}

# Create data directory with compatibility mode support
create_data_dir() {
    local target="$1"
    shift
    local fallback="$1"
    shift
    
    if [ "$COMPAT_MODE" = false ] || mountpoint -q "$target" 2>/dev/null; then
        for dir in "$@"; do
            mkdir -p "$target/$dir"
        done
    else
        for dir in "$@"; do
            mkdir -p "$fallback/$dir"
        done
        [ ! -d "$target" ] && ln -sf "$fallback" "$target"
    fi
}

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
        --yes|-y)
            YES=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Get script directory first (needed for safe_source)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize logging (after SCRIPT_DIR is set)
setup_logging

echo -e "${BLUE}HostArchy Installation Script v${VERSION}${NC}"
echo "=========================================="
echo "Installation log: $LOGFILE"
echo ""

# Early checks - fail fast
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (use sudo)${NC}"
    exit 1
fi

if [ ! -f /etc/arch-release ]; then
    echo -e "${RED}Error: This script must be run on Arch Linux${NC}"
    exit 1
fi

# Check dependencies
check_dependencies

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

# Check internet connectivity
if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo -e "${RED}Error: No internet connectivity detected${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Internet connectivity confirmed${NC}"

# Check if /db mount exists or if we're in compatibility mode
if mountpoint -q /db 2>/dev/null; then
    echo -e "${GREEN}✓ /db mount detected (Strict Mode)${NC}"
    COMPAT_MODE=false
elif [ "$PROFILE" = "performance" ] || [ "$PROFILE" = "database" ]; then
    echo -e "${RED}Error: /db mount required for $PROFILE profile${NC}"
    exit 1
else
    echo -e "${YELLOW}⚠ /db mount not detected (Compatibility Mode)${NC}"
    if [ "$YES" = false ]; then
        read -p "Continue without physical isolation? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo -e "${YELLOW}  Auto-accepted (--yes flag)${NC}"
    fi
    COMPAT_MODE=true
fi

# Create HostArchy directories
echo -e "${YELLOW}Creating directory structure...${NC}"
mkdir -p "$HOSTARCHY_DIR"/{bin,lib,templates}
mkdir -p "$HOSTARCHY_ETC"/{config,profiles,state,hooks}

# Create data directories using helper function
create_data_dir /srv /var/lib/hostarchy/srv http git backups
create_data_dir /db /var/lib/hostarchy/db mariadb postgres redis metadata

echo -e "${GREEN}✓ Directory structure created${NC}"

# Copy files to installation directory
echo -e "${YELLOW}Installing HostArchy files...${NC}"

# Copy binaries (use -n to avoid overwriting existing)
if [ -f "$SCRIPT_DIR/bin/hostarchy" ]; then
    cp -n "$SCRIPT_DIR/bin/hostarchy" "$HOSTARCHY_DIR/bin/hostarchy" 2>/dev/null || \
    cp "$SCRIPT_DIR/bin/hostarchy" "$HOSTARCHY_DIR/bin/hostarchy"
    chmod +x "$HOSTARCHY_DIR/bin/hostarchy"
fi

# Copy libraries
if [ -d "$SCRIPT_DIR/lib" ]; then
    cp -rn "$SCRIPT_DIR/lib"/* "$HOSTARCHY_DIR/lib/" 2>/dev/null || \
    cp -r "$SCRIPT_DIR/lib"/* "$HOSTARCHY_DIR/lib/" 2>/dev/null || true
    chmod +x "$HOSTARCHY_DIR/lib"/*.sh 2>/dev/null || true
fi

# Copy templates
if [ -d "$SCRIPT_DIR/templates" ]; then
    cp -rn "$SCRIPT_DIR/templates"/* "$HOSTARCHY_DIR/templates/" 2>/dev/null || \
    cp -r "$SCRIPT_DIR/templates"/* "$HOSTARCHY_DIR/templates/" 2>/dev/null || true
fi

# Copy profiles
if [ -d "$SCRIPT_DIR/profiles" ]; then
    mkdir -p "$HOSTARCHY_DIR/profiles"
    cp -rn "$SCRIPT_DIR/profiles"/* "$HOSTARCHY_DIR/profiles/" 2>/dev/null || \
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

# Define base packages
BASE_PACKAGES=(
    base linux linux-firmware systemd-sysvcompat
    git base-devel openssh neovim htop rsync
    nginx php php-fpm php-opcache
    mariadb postgresql redis fail2ban nftables
)

# Define profile-specific packages
PROFILE_PACKAGES=()
case $PROFILE in
    performance|database)
        PROFILE_PACKAGES+=(btrfs-progs xfsprogs)
        ;;
esac

# Install all packages in a single call
pacman -Sy --noconfirm --needed "${BASE_PACKAGES[@]}" "${PROFILE_PACKAGES[@]}"

echo -e "${GREEN}✓ Packages installed${NC}"

# Apply profile configuration
echo -e "${YELLOW}Applying profile: $PROFILE${NC}"
if safe_source "profiles/$PROFILE.sh"; then
    apply_profile
else
    echo -e "${YELLOW}⚠ Profile script not found, using defaults${NC}"
fi

# Apply system tuning
echo -e "${YELLOW}Applying system tuning...${NC}"
safe_source "lib/system-tuning.sh" && apply_system_tuning

# Configure services
echo -e "${YELLOW}Configuring services...${NC}"
safe_source "lib/service-config.sh" && configure_services "$PROFILE"

# Install pacman hook
echo -e "${YELLOW}Installing pacman hook...${NC}"
mkdir -p /etc/pacman.d/hooks
if [ -f "$SCRIPT_DIR/pacman-hooks/hostarchy.hook" ]; then
    cp -n "$SCRIPT_DIR/pacman-hooks/hostarchy.hook" /etc/pacman.d/hooks/hostarchy.hook 2>/dev/null || \
    cp "$SCRIPT_DIR/pacman-hooks/hostarchy.hook" /etc/pacman.d/hooks/hostarchy.hook
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

