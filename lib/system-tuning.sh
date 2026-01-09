#!/bin/bash
# HostArchy System Tuning
# Applies kernel and system optimizations for web hosting

# Try to source common.sh from multiple possible locations
if [ -f "$(dirname "$0")/common.sh" ]; then
    source "$(dirname "$0")/common.sh"
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

# Define backup_file if not available
if ! command -v backup_file >/dev/null 2>&1; then
    backup_file() {
        local file="$1"
        if [ -f "$file" ]; then
            local backup="${file}.hostarchy.$(date +%Y%m%d_%H%M%S)"
            cp "$file" "$backup"
            echo "$backup"
        fi
    }
fi

# Apply all system tuning optimizations
apply_system_tuning() {
    log_info "Applying system tuning optimizations..."
    
    local sysctl_file="/etc/sysctl.d/99-hostarchy.conf"
    
    # Backup existing file
    if [ -f "$sysctl_file" ]; then
        backup_file "$sysctl_file"
    fi
    
    # Create new sysctl configuration
    cat > "$sysctl_file" <<'EOF'
# HostArchy System Tuning Configuration
# Generated automatically - DO NOT EDIT MANUALLY

# Network optimizations
# TCP BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Increase connection queue
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096

# TCP TIME_WAIT socket reuse
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# Increase connection tracking
net.netfilter.nf_conntrack_max = 262144

# Buffer sizes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Virtual Memory optimizations
vm.swappiness = 10
vm.dirty_ratio = 30
vm.dirty_background_ratio = 10

# File descriptors
fs.file-max = 2097152

# Security hardening
kernel.kptr_restrict = 1
kernel.dmesg_restrict = 1

# IP forwarding (disabled by default for security)
# net.ipv4.ip_forward = 0
# net.ipv6.conf.all.forwarding = 0

# TCP SYN cookies (DDoS protection)
net.ipv4.tcp_syncookies = 1

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# Ignore ICMP ping
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Log martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
EOF
    
    # Apply sysctl settings
    sysctl -p "$sysctl_file" >/dev/null 2>&1 || true
    
    log_success "System tuning configuration applied"
    
    # Set file permissions
    chmod 644 "$sysctl_file"
    
    # Apply limits for file descriptors
    apply_limits
    
    log_success "System tuning complete"
}

# Apply system limits
apply_limits() {
    local limits_file="/etc/security/limits.d/99-hostarchy.conf"
    
    cat > "$limits_file" <<'EOF'
# HostArchy System Limits
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF
    
    chmod 644 "$limits_file"
    log_info "System limits configured"
}

# Check if BBR is available
check_bbr() {
    if modprobe tcp_bbr >/dev/null 2>&1; then
        echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
        log_success "TCP BBR module enabled"
        return 0
    else
        log_warning "TCP BBR module not available (may require kernel 4.9+)"
        return 1
    fi
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    apply_system_tuning
fi

