#!/bin/bash
# HostArchy Performance Profile
# High-performance web hosting with optimized database configuration

# Try to source common.sh from multiple possible locations
if [ -f "$(dirname "$0")/../lib/common.sh" ]; then
    source "$(dirname "$0")/../lib/common.sh"
elif [ -f "/usr/local/hostarchy/lib/common.sh" ]; then
    source "/usr/local/hostarchy/lib/common.sh"
else
    # Fallback: define minimal functions
    log_info() { echo "[INFO] $*"; }
    log_success() { echo "[SUCCESS] $*"; }
    log_warning() { echo "[WARNING] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

# Define apply_sysctl if not available
if ! command -v apply_sysctl >/dev/null 2>&1; then
    apply_sysctl() {
        local key="$1"
        local value="$2"
        local sysctl_file="/etc/sysctl.d/99-hostarchy.conf"
        if grep -q "^${key}" "$sysctl_file" 2>/dev/null; then
            sed -i "s|^${key}.*|${key} = ${value}|" "$sysctl_file"
        else
            echo "${key} = ${value}" >> "$sysctl_file"
        fi
        sysctl -w "${key}=${value}" >/dev/null 2>&1 || true
    }
fi

# Apply performance profile
apply_profile() {
    log_info "Applying Performance profile..."
    
    # Check for required mounts
    if ! mountpoint -q /db 2>/dev/null; then
        log_error "Performance profile requires /db mount point"
        log_error "Please ensure /db is mounted before applying this profile"
        exit 1
    fi
    
    local profile_dir="/etc/hostarchy/profiles"
    mkdir -p "$profile_dir"
    
    # Save profile configuration
    cat > "$profile_dir/performance.conf" <<'EOF'
PROFILE_NAME=performance
PROFILE_DESCRIPTION=High-performance web hosting
STACK=nginx,php-fpm,mariadb,postgresql,redis
DATABASES=required
OPTIMIZATION_LEVEL=aggressive
COMPATIBILITY_MODE=not_allowed
REQUIRES_DB_MOUNT=true
EOF
    
    log_info "Performance profile configuration:"
    log_info "  - Web server: Nginx (optimized)"
    log_info "  - PHP runtime: PHP-FPM with JIT enabled"
    log_info "  - Databases: MariaDB, PostgreSQL, Redis (required)"
    log_info "  - Optimization: Aggressive"
    log_info "  - Compatibility mode: Not allowed (/db mount required)"
    
    # Apply aggressive system tuning
    log_info "Applying aggressive system tuning..."
    
    # Additional sysctl optimizations for performance
    local sysctl_file="/etc/sysctl.d/99-hostarchy.conf"
    if [ -f "$sysctl_file" ]; then
        # Increase dirty ratio for better write performance
        apply_sysctl "vm.dirty_ratio" "40"
        apply_sysctl "vm.dirty_background_ratio" "15"
        
        # Optimize for database workloads
        apply_sysctl "vm.overcommit_memory" "1"
        apply_sysctl "vm.overcommit_ratio" "80"
    fi
    
    # Configure PHP-FPM for high performance
    if [ -f /etc/php/php-fpm.d/www.conf ]; then
        sed -i 's/^pm.max_children = .*/pm.max_children = 100/' /etc/php/php-fpm.d/www.conf
        sed -i 's/^pm.start_servers = .*/pm.start_servers = 20/' /etc/php/php-fpm.d/www.conf
        sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 20/' /etc/php/php-fpm.d/www.conf
        sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 70/' /etc/php/php-fpm.d/www.conf
    fi
    
    # Configure Nginx for high performance
    if [ -f /etc/nginx/nginx.conf ]; then
        sed -i 's/^worker_connections .*/worker_connections 16384;/' /etc/nginx/nginx.conf
    fi
    
    log_success "Performance profile applied"
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    apply_profile
fi

