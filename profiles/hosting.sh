#!/bin/bash
# HostArchy Hosting Profile
# General-purpose web hosting configuration

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

# Apply hosting profile
apply_profile() {
    log_info "Applying Hosting profile..."
    
    local profile_dir="/etc/hostarchy/profiles"
    mkdir -p "$profile_dir"
    
    # Save profile configuration
    cat > "$profile_dir/hosting.conf" <<'EOF'
PROFILE_NAME=hosting
PROFILE_DESCRIPTION=General-purpose web hosting
STACK=nginx,php-fpm
DATABASES=optional
OPTIMIZATION_LEVEL=balanced
COMPATIBILITY_MODE=allowed
EOF
    
    log_info "Hosting profile configuration:"
    log_info "  - Web server: Nginx"
    log_info "  - PHP runtime: PHP-FPM"
    log_info "  - Databases: Optional (not automatically configured)"
    log_info "  - Optimization: Balanced"
    log_info "  - Compatibility mode: Allowed (single partition)"
    
    # Apply stack-specific configurations
    log_info "Stack components will be configured via service-config.sh"
    
    log_success "Hosting profile applied"
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    apply_profile
fi

