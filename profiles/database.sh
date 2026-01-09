#!/bin/bash
# HostArchy Database Profile
# Specialized database server configuration

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

# Apply database profile
apply_profile() {
    log_info "Applying Database profile..."
    
    # Check for required mounts
    if ! mountpoint -q /db 2>/dev/null; then
        log_error "Database profile requires /db mount point"
        log_error "Please ensure /db is mounted before applying this profile"
        exit 1
    fi
    
    local profile_dir="/etc/hostarchy/profiles"
    mkdir -p "$profile_dir"
    
    # Save profile configuration
    cat > "$profile_dir/database.conf" <<'EOF'
PROFILE_NAME=database
PROFILE_DESCRIPTION=Specialized database server
STACK=mariadb,postgresql,redis
DATABASES=required
OPTIMIZATION_LEVEL=aggressive
COMPATIBILITY_MODE=not_allowed
REQUIRES_DB_MOUNT=true
FOCUS=database_performance
EOF
    
    log_info "Database profile configuration:"
    log_info "  - Focus: Database server"
    log_info "  - Databases: MariaDB, PostgreSQL, Redis (required)"
    log_info "  - Optimization: Aggressive (database-focused)"
    log_info "  - Compatibility mode: Not allowed (/db mount required)"
    log_info "  - Web stack: Not included (database-only)"
    
    # Apply database-focused system tuning
    log_info "Applying database-focused system tuning..."
    
    local sysctl_file="/etc/sysctl.d/99-hostarchy.conf"
    if [ -f "$sysctl_file" ]; then
        # Optimize for database workloads
        apply_sysctl "vm.swappiness" "5"
        apply_sysctl "vm.dirty_ratio" "25"
        apply_sysctl "vm.dirty_background_ratio" "10"
        apply_sysctl "vm.overcommit_memory" "2"
        apply_sysctl "vm.overcommit_ratio" "90"
        
        # Increase shared memory for PostgreSQL
        apply_sysctl "kernel.shmmax" "68719476736"
        apply_sysctl "kernel.shmall" "16777216"
    fi
    
    # Configure MariaDB for performance
    if command -v mysql >/dev/null 2>&1; then
        local mariadb_conf="/etc/mysql/my.cnf"
        if [ ! -f "$mariadb_conf" ]; then
            mkdir -p /etc/mysql
            touch "$mariadb_conf"
        fi
        
        cat >> "$mariadb_conf" <<'EOF'

[mysqld]
# Performance tuning
innodb_buffer_pool_size = 2G
innodb_log_file_size = 512M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
max_connections = 500
query_cache_type = 1
query_cache_size = 256M
tmp_table_size = 256M
max_heap_table_size = 256M
EOF
    fi
    
    # Configure PostgreSQL for performance
    if [ -d /var/lib/postgres/data ] || [ -d /db/postgres ]; then
        local pg_data_dir="/var/lib/postgres/data"
        if [ -d /db/postgres ]; then
            pg_data_dir="/db/postgres"
        fi
        
        local postgresql_conf="$pg_data_dir/postgresql.conf"
        if [ -f "$postgresql_conf" ]; then
            # Backup
            backup_file "$postgresql_conf"
            
            # Optimize PostgreSQL settings
            sed -i 's/^#shared_buffers = .*/shared_buffers = 2GB/' "$postgresql_conf"
            sed -i 's/^shared_buffers = .*/shared_buffers = 2GB/' "$postgresql_conf"
            
            sed -i 's/^#effective_cache_size = .*/effective_cache_size = 6GB/' "$postgresql_conf"
            sed -i 's/^effective_cache_size = .*/effective_cache_size = 6GB/' "$postgresql_conf"
            
            sed -i 's/^#maintenance_work_mem = .*/maintenance_work_mem = 512MB/' "$postgresql_conf"
            sed -i 's/^maintenance_work_mem = .*/maintenance_work_mem = 512MB/' "$postgresql_conf"
            
            sed -i 's/^#checkpoint_completion_target = .*/checkpoint_completion_target = 0.9/' "$postgresql_conf"
            sed -i 's/^checkpoint_completion_target = .*/checkpoint_completion_target = 0.9/' "$postgresql_conf"
            
            sed -i 's/^#wal_buffers = .*/wal_buffers = 16MB/' "$postgresql_conf"
            sed -i 's/^wal_buffers = .*/wal_buffers = 16MB/' "$postgresql_conf"
        fi
    fi
    
    log_success "Database profile applied"
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    apply_profile
fi

