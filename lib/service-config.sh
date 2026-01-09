#!/bin/bash
# HostArchy Service Configuration
# Configures web stack services (nginx, PHP-FPM, databases, etc.)

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
    backup_file() {
        local file="$1"
        if [ -f "$file" ]; then
            local backup="${file}.hostarchy.$(date +%Y%m%d_%H%M%S)"
            cp "$file" "$backup"
            echo "$backup"
        fi
    }
    enable_service() {
        local service="$1"
        systemctl enable "$service" >/dev/null 2>&1
        systemctl start "$service" >/dev/null 2>&1
    }
    restart_service() {
        local service="$1"
        if systemctl is-active --quiet "$service"; then
            systemctl restart "$service" >/dev/null 2>&1
        else
            enable_service "$service"
        fi
    }
    test_nginx_config() {
        if nginx -t >/dev/null 2>&1; then
            return 0
        else
            nginx -t
            return 1
        fi
    }
fi

# Configure all services
configure_services() {
    local profile="${1:-hosting}"
    
    log_info "Configuring services for profile: $profile"
    
    configure_nginx
    configure_php_fpm
    configure_ssh
    configure_fail2ban
    configure_firewall
    
    case "$profile" in
        database|performance)
            configure_mariadb
            configure_postgresql
            ;;
        *)
            # Optional database setup for hosting profile
            log_info "Skipping database configuration (use performance/database profile)"
            ;;
    esac
    
    configure_redis
    
    log_success "Service configuration complete"
}

# Configure Nginx
configure_nginx() {
    log_info "Configuring Nginx..."
    
    local nginx_conf="/etc/nginx/nginx.conf"
    
    # Backup existing config
    if [ -f "$nginx_conf" ]; then
        backup_file "$nginx_conf"
    fi
    
    # Create optimized nginx.conf
    cat > "$nginx_conf" <<'EOF'
user http;
worker_processes auto;
worker_rlimit_nofile 65535;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events {
    worker_connections 8192;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;
    
    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss 
               application/rss+xml font/truetype font/opentype 
               application/vnd.ms-fontobject image/svg+xml;
    gzip_disable "msie6";
    
    # File descriptor cache
    open_file_cache max=10000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;
    
    # Client limits
    client_max_body_size 100M;
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    
    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
    
    # Create sites directories
    mkdir -p /etc/nginx/{sites-available,sites-enabled,conf.d}
    
    # Create default site
    cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /srv/http/default;
    index index.html index.htm;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF
    
    # Enable default site
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    
    # Create default web root
    mkdir -p /srv/http/default
    echo "<h1>HostArchy</h1><p>Web server is running!</p>" > /srv/http/default/index.html
    chown -R http:http /srv/http
    
    # Test configuration
    if test_nginx_config; then
        enable_service nginx
    else
        log_error "Nginx configuration failed"
        return 1
    fi
}

# Configure PHP-FPM
configure_php_fpm() {
    log_info "Configuring PHP-FPM..."
    
    local php_ini="/etc/php/php.ini"
    local php_fpm_conf="/etc/php/php-fpm.d/www.conf"
    
    # Backup existing configs
    if [ -f "$php_ini" ]; then
        backup_file "$php_ini"
    fi
    if [ -f "$php_fpm_conf" ]; then
        backup_file "$php_fpm_conf"
    fi
    
    # Optimize PHP settings
    sed -i 's/^;opcache.enable=.*/opcache.enable=1/' "$php_ini" 2>/dev/null || true
    sed -i 's/^opcache.enable=.*/opcache.enable=1/' "$php_ini" 2>/dev/null || true
    
    sed -i 's/^;opcache.memory_consumption=.*/opcache.memory_consumption=256/' "$php_ini" 2>/dev/null || true
    sed -i 's/^opcache.memory_consumption=.*/opcache.memory_consumption=256/' "$php_ini" 2>/dev/null || true
    
    # Enable JIT if available (PHP 8+)
    if php -v | grep -q "PHP 8\."; then
        sed -i 's/^;opcache.jit=.*/opcache.jit=tracing/' "$php_ini" 2>/dev/null || true
        sed -i 's/^opcache.jit=.*/opcache.jit=tracing/' "$php_ini" 2>/dev/null || true
        sed -i 's/^;opcache.jit_buffer_size=.*/opcache.jit_buffer_size=256M/' "$php_ini" 2>/dev/null || true
    fi
    
    # Configure PHP-FPM pool
    if [ -f "$php_fpm_conf" ]; then
        # Use Unix socket
        sed -i 's/^listen = .*/listen = \/run\/php-fpm\/php-fpm.sock/' "$php_fpm_conf"
        sed -i 's/^;listen.owner = .*/listen.owner = http/' "$php_fpm_conf"
        sed -i 's/^;listen.group = .*/listen.group = http/' "$php_fpm_conf"
        sed -i 's/^;listen.mode = .*/listen.mode = 0660/' "$php_fpm_conf"
        
        # Performance settings
        sed -i 's/^pm = .*/pm = dynamic/' "$php_fpm_conf"
        sed -i 's/^;pm.max_children = .*/pm.max_children = 50/' "$php_fpm_conf"
        sed -i 's/^pm.max_children = .*/pm.max_children = 50/' "$php_fpm_conf"
        sed -i 's/^;pm.start_servers = .*/pm.start_servers = 5/' "$php_fpm_conf"
        sed -i 's/^pm.start_servers = .*/pm.start_servers = 5/' "$php_fpm_conf"
        sed -i 's/^;pm.min_spare_servers = .*/pm.min_spare_servers = 5/' "$php_fpm_conf"
        sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 5/' "$php_fpm_conf"
        sed -i 's/^;pm.max_spare_servers = .*/pm.max_spare_servers = 35/' "$php_fpm_conf"
        sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 35/' "$php_fpm_conf"
    fi
    
    enable_service php-fpm
    log_success "PHP-FPM configured"
}

# Configure SSH
configure_ssh() {
    log_info "Configuring SSH..."
    
    local sshd_config="/etc/ssh/sshd_config"
    
    if [ ! -f "$sshd_config" ]; then
        log_warning "SSH config file not found, skipping"
        return 0
    fi
    
    # Backup
    backup_file "$sshd_config"
    
    # Security hardening
    sed -i 's/^#PermitRootLogin .*/PermitRootLogin prohibit-password/' "$sshd_config"
    sed -i 's/^PermitRootLogin .*/PermitRootLogin prohibit-password/' "$sshd_config"
    
    sed -i 's/^#PasswordAuthentication .*/PasswordAuthentication no/' "$sshd_config"
    sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' "$sshd_config"
    
    # Change port (optional, uncomment if needed)
    # sed -i 's/^#Port 22/Port 2222/' "$sshd_config"
    # sed -i 's/^Port 22/Port 2222/' "$sshd_config"
    
    # Disable empty passwords
    sed -i 's/^#PermitEmptyPasswords .*/PermitEmptyPasswords no/' "$sshd_config"
    sed -i 's/^PermitEmptyPasswords .*/PermitEmptyPasswords no/' "$sshd_config"
    
    # Disable X11 forwarding if not needed
    sed -i 's/^#X11Forwarding .*/X11Forwarding no/' "$sshd_config"
    sed -i 's/^X11Forwarding .*/X11Forwarding no/' "$sshd_config"
    
    # Test SSH config
    if sshd -t >/dev/null 2>&1; then
        restart_service sshd
        log_success "SSH configured"
    else
        log_error "SSH configuration invalid"
        sshd -t
        return 1
    fi
}

# Configure Fail2Ban
configure_fail2ban() {
    log_info "Configuring Fail2Ban..."
    
    local jail_local="/etc/fail2ban/jail.local"
    
    # Backup if exists
    if [ -f "$jail_local" ]; then
        backup_file "$jail_local"
    fi
    
    # Create jail.local
    cat > "$jail_local" <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
EOF
    
    chmod 644 "$jail_local"
    enable_service fail2ban
    log_success "Fail2Ban configured"
}

# Configure Firewall (nftables)
configure_firewall() {
    log_info "Configuring nftables firewall..."
    
    local nftables_conf="/etc/nftables.conf"
    
    # Backup
    if [ -f "$nftables_conf" ]; then
        backup_file "$nftables_conf"
    fi
    
    # Create firewall rules
    cat > "$nftables_conf" <<'EOF'
#!/usr/bin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        
        # Allow loopback
        iif lo accept
        
        # Allow established/related connections
        ct state established,related accept
        
        # Allow ICMP (ping)
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept
        
        # Allow SSH (port 22)
        tcp dport 22 accept
        
        # Allow HTTP/HTTPS
        tcp dport 80 accept
        tcp dport 443 accept
        
        # Drop everything else
        drop
    }
    
    chain forward {
        type filter hook forward priority filter; policy drop;
    }
    
    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF
    
    chmod 644 "$nftables_conf"
    
    # Test and enable
    if nft -f "$nftables_conf" >/dev/null 2>&1; then
        enable_service nftables
        log_success "Firewall configured"
    else
        log_warning "nftables configuration test failed, checking manually"
        nft -f "$nftables_conf" || log_error "nftables configuration invalid"
    fi
}

# Configure MariaDB
configure_mariadb() {
    log_info "Configuring MariaDB..."
    
    # Initialize database if needed
    if [ ! -d /var/lib/mysql/mysql ]; then
        mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql >/dev/null 2>&1 || true
    fi
    
    # Set datadir to /db/mariadb if mounted
    if mountpoint -q /db 2>/dev/null; then
        if [ ! -d /db/mariadb ]; then
            mkdir -p /db/mariadb
            chown mysql:mysql /db/mariadb
        fi
        
        # Configure MariaDB to use /db/mariadb
        local mariadb_conf="/etc/mysql/my.cnf"
        if [ ! -f "$mariadb_conf" ]; then
            mkdir -p /etc/mysql
            touch "$mariadb_conf"
        fi
        
        if ! grep -q "^datadir" "$mariadb_conf" 2>/dev/null; then
            echo "[mysqld]" >> "$mariadb_conf"
            echo "datadir = /db/mariadb" >> "$mariadb_conf"
        fi
    fi
    
    enable_service mariadb
    log_success "MariaDB configured"
}

# Configure PostgreSQL
configure_postgresql() {
    log_info "Configuring PostgreSQL..."
    
    # Initialize database if needed
    if [ ! -d /var/lib/postgres/data ]; then
        # Determine data directory
        local pg_data_dir="/var/lib/postgres/data"
        if mountpoint -q /db 2>/dev/null; then
            pg_data_dir="/db/postgres"
            mkdir -p "$pg_data_dir"
            chown postgres:postgres "$pg_data_dir"
        fi
        
        sudo -u postgres initdb -D "$pg_data_dir" >/dev/null 2>&1 || true
    fi
    
    enable_service postgresql
    log_success "PostgreSQL configured"
}

# Configure Redis
configure_redis() {
    log_info "Configuring Redis..."
    
    local redis_conf="/etc/redis/redis.conf"
    
    if [ -f "$redis_conf" ]; then
        # Backup
        backup_file "$redis_conf"
        
        # Set data directory to /db/redis if mounted
        if mountpoint -q /db 2>/dev/null; then
            if [ ! -d /db/redis ]; then
                mkdir -p /db/redis
                chown redis:redis /db/redis
            fi
            
            sed -i 's|^dir .*|dir /db/redis|' "$redis_conf"
        fi
        
        # Security: bind to localhost only by default
        if ! grep -q "^bind" "$redis_conf"; then
            sed -i 's/^# bind .*/bind 127.0.0.1/' "$redis_conf" || true
        fi
    fi
    
    enable_service redis
    log_success "Redis configured"
}

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    configure_services "${1:-hosting}"
fi

