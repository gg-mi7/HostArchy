#!/bin/bash
# HostArchy Common Library
# Shared functions and utilities

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check if file exists and is readable
check_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        return 1
    fi
    if [ ! -r "$file" ]; then
        log_error "File not readable: $file"
        return 1
    fi
    return 0
}

# Backup a file
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup="${file}.hostarchy.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        log_info "Backed up $file to $backup"
        echo "$backup"
    fi
}

# Generate checksum for file
get_checksum() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        md5sum "$file" | cut -d' ' -f1
    fi
}

# Apply sysctl settings
apply_sysctl() {
    local key="$1"
    local value="$2"
    local sysctl_file="/etc/sysctl.d/99-hostarchy.conf"
    
    # Create file if it doesn't exist
    if [ ! -f "$sysctl_file" ]; then
        touch "$sysctl_file"
        echo "# HostArchy sysctl configuration" >> "$sysctl_file"
        echo "# Generated on $(date)" >> "$sysctl_file"
        echo "" >> "$sysctl_file"
    fi
    
    # Check if setting already exists
    if grep -q "^${key}" "$sysctl_file" 2>/dev/null; then
        sed -i "s|^${key}.*|${key} = ${value}|" "$sysctl_file"
    else
        echo "${key} = ${value}" >> "$sysctl_file"
    fi
    
    # Apply immediately
    sysctl -w "${key}=${value}" >/dev/null 2>&1 || true
}

# Enable and start systemd service
enable_service() {
    local service="$1"
    systemctl enable "$service" >/dev/null 2>&1
    systemctl start "$service" >/dev/null 2>&1
    log_success "Service enabled and started: $service"
}

# Restart systemd service
restart_service() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        systemctl restart "$service" >/dev/null 2>&1
        log_info "Service restarted: $service"
    else
        enable_service "$service"
    fi
}

# Configure nginx site
configure_nginx_site() {
    local site_name="$1"
    local server_name="$2"
    local root_dir="$3"
    
    local sites_available="/etc/nginx/sites-available"
    local sites_enabled="/etc/nginx/sites-enabled"
    
    mkdir -p "$sites_available" "$sites_enabled"
    
    # Create site configuration
    cat > "$sites_available/$site_name" <<EOF
server {
    listen 80;
    server_name $server_name;
    root $root_dir;
    index index.php index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ \.php$ {
        fastcgi_pass unix:/run/php-fpm/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location ~ /\. {
        deny all;
    }
}
EOF
    
    # Create symlink if it doesn't exist
    if [ ! -L "$sites_enabled/$site_name" ]; then
        ln -s "$sites_available/$site_name" "$sites_enabled/$site_name"
    fi
    
    log_success "Nginx site configured: $site_name"
}

# Test nginx configuration
test_nginx_config() {
    if nginx -t >/dev/null 2>&1; then
        log_success "Nginx configuration is valid"
        return 0
    else
        log_error "Nginx configuration is invalid"
        nginx -t
        return 1
    fi
}

