# HostArchy Installation Guide

This guide walks you through installing and configuring HostArchy on a fresh Arch Linux system.

## Prerequisites

- ✅ Vanilla Arch Linux installed (see [ARCHGUIDE.md](ARCHGUIDE.md))
- ✅ Root access (or sudo privileges)
- ✅ Internet connection
- ✅ For Performance/Database profiles: `/srv` and `/db` partitions mounted (optional for hosting profile)

## Quick Start

```bash
# Clone HostArchy repository
git clone https://github.com/hostarchy/hostarchy.git /usr/local/hostarchy

# Enter directory
cd /usr/local/hostarchy

# Make installer executable
chmod +x install.sh

# Run installer
sudo ./install.sh --profile=hosting
```

## Installation Steps

### 1. Clone HostArchy Repository

Clone the HostArchy repository to `/usr/local/hostarchy`:

```bash
git clone https://github.com/hostarchy/hostarchy.git /usr/local/hostarchy
```

If the repository is already cloned elsewhere, you can copy it:

```bash
# If you cloned to a different location
sudo cp -r /path/to/hostarchy /usr/local/hostarchy
```

### 2. Navigate to HostArchy Directory

```bash
cd /usr/local/hostarchy
```

### 3. Verify Installation Files

Check that all required files are present:

```bash
ls -la install.sh bin/ lib/ profiles/ templates/ pacman-hooks/
```

You should see:
- `install.sh` - Main installation script
- `bin/hostarchy` - CLI tool
- `lib/` - Library scripts
- `profiles/` - Profile definitions
- `templates/` - Configuration templates
- `pacman-hooks/` - Pacman hooks

### 4. Make Scripts Executable

```bash
sudo chmod +x install.sh
sudo chmod +x bin/hostarchy
sudo chmod +x lib/*.sh
sudo chmod +x profiles/*.sh
```

### 5. Review Available Profiles

HostArchy supports three profiles:

#### Hosting Profile (Default)
- **Use case**: General-purpose web hosting
- **Requirements**: Single partition (compatibility mode allowed)
- **Includes**: Nginx, PHP-FPM, optional databases
- **Optimization**: Balanced

#### Performance Profile
- **Use case**: High-performance web hosting
- **Requirements**: Separate `/srv` and `/db` partitions (required)
- **Includes**: Nginx (optimized), PHP-FPM with JIT, MariaDB, PostgreSQL, Redis
- **Optimization**: Aggressive

#### Database Profile
- **Use case**: Dedicated database server
- **Requirements**: Separate `/db` partition (required)
- **Includes**: MariaDB, PostgreSQL, Redis (optimized for databases)
- **Optimization**: Database-focused

### 6. Run Installation

#### For Hosting Profile (Recommended for most users):

```bash
sudo ./install.sh --profile=hosting
```

Or:

```bash
sudo ./install.sh --profile hosting
```

#### For Performance Profile:

```bash
# Ensure /srv and /db are mounted first
mount | grep -E "(/srv|/db)"

# Then install
sudo ./install.sh --profile=performance
```

#### For Database Profile:

```bash
# Ensure /db is mounted first
mount | grep /db

# Then install
sudo ./install.sh --profile=database
```

### 7. Installation Process

The installer will:

1. **Pre-flight Checks**
   - Verify Arch Linux installation
   - Check for required mounts
   - Test internet connectivity
   - Verify root access

2. **Create Directory Structure**
   - `/etc/hostarchy/` - Configuration and state
   - `/usr/local/hostarchy/` - Installed files
   - `/srv/http/`, `/srv/git/`, `/srv/backups/` - Web content directories
   - `/db/mariadb/`, `/db/postgres/`, `/db/redis/` - Database directories

3. **Install Packages**
   - Nginx web server
   - PHP 8.x with PHP-FPM
   - MariaDB, PostgreSQL, Redis (depending on profile)
   - Fail2Ban, nftables firewall
   - Additional performance packages (for performance/database profiles)

4. **Apply Profile Configuration**
   - Configure stack components
   - Apply profile-specific optimizations

5. **Apply System Tuning**
   - Kernel parameters via sysctl
   - TCP BBR congestion control
   - Network optimizations
   - Memory optimizations

6. **Configure Services**
   - Nginx with optimized configuration
   - PHP-FPM with OPcache and JIT (if available)
   - SSH hardening
   - Fail2Ban with SSH and Nginx jails
   - nftables firewall (default DROP policy)

7. **Install Pacman Hook**
   - Automatically re-applies HostArchy configuration after updates

8. **Save Installation State**
   - Records profile, installation date, and configuration

### 8. Verify Installation

After installation completes, verify the installation:

```bash
# Check HostArchy status
hostarchy status

# Check services
systemctl status nginx
systemctl status php-fpm
systemctl status fail2ban

# Check system tuning
cat /etc/sysctl.d/99-hostarchy.conf

# Test web server (should show HostArchy default page)
curl http://localhost
```

### 9. Post-Installation Configuration

#### Configure SSH (Optional)

If you want to change the SSH port, edit `/etc/ssh/sshd_config`:

```bash
sudo nano /etc/ssh/sshd_config
# Change: #Port 22 to Port 2222 (or your preferred port)

# Update firewall rule
sudo nano /etc/nftables.conf
# Change: tcp dport 22 to tcp dport 2222

# Restart services
sudo systemctl restart sshd
sudo systemctl restart nftables
```

#### Configure Firewall Rules

Edit `/etc/nftables.conf` to allow additional ports if needed:

```bash
sudo nano /etc/nftables.conf
```

Common additions:
- Allow additional ports for web applications
- Allow monitoring ports
- Configure port forwarding rules

After editing, test and reload:

```bash
sudo nft -f /etc/nftables.conf
sudo systemctl restart nftables
```

#### Create Your First Website

1. Create a site directory:
   ```bash
   sudo mkdir -p /srv/http/example.com
   sudo chown -R http:http /srv/http/example.com
   ```

2. Create a test file:
   ```bash
   echo "<h1>Hello from HostArchy!</h1>" | sudo tee /srv/http/example.com/index.html
   ```

3. Create Nginx configuration:
   ```bash
   sudo nano /etc/nginx/sites-available/example.com
   ```

   Use the template from `/usr/local/hostarchy/templates/nginx-site.conf` or:

   ```nginx
   server {
       listen 80;
       server_name example.com www.example.com;
       root /srv/http/example.com;
       index index.html index.php;
       
       location / {
           try_files $uri $uri/ =404;
       }
   }
   ```

4. Enable the site:
   ```bash
   sudo ln -s /etc/nginx/sites-available/example.com /etc/nginx/sites-enabled/
   sudo nginx -t
   sudo systemctl reload nginx
   ```

## Using the HostArchy CLI

The `hostarchy` command provides easy management:

### Check Status

```bash
# Human-readable status
hostarchy status

# JSON output (for monitoring/automation)
hostarchy status --json
```

### Manage Profiles

```bash
# View current profile
hostarchy profile

# Change profile
sudo hostarchy profile --profile=performance

# After changing profile, re-apply configuration
sudo hostarchy apply
```

### Run Checks

```bash
# Pre-flight checks
hostarchy check
```

### Re-apply Configuration

```bash
# After manual changes or package updates
sudo hostarchy apply
```

### Show Version

```bash
hostarchy version
```

## Updating HostArchy

To update HostArchy:

```bash
# Navigate to installation directory
cd /usr/local/hostarchy

# Pull latest changes
sudo git pull

# Re-apply configuration (optional, but recommended)
sudo hostarchy apply
```

## Maintenance

### After System Updates

The pacman hook automatically runs `hostarchy apply` after certain package updates (nginx, php, linux kernel). However, you can manually trigger it:

```bash
sudo hostarchy apply
```

### Checking Service Status

```bash
# All services at once
hostarchy status

# Individual services
systemctl status nginx
systemctl status php-fpm
systemctl status mariadb
systemctl status postgresql
systemctl status redis
systemctl status fail2ban
```

### Viewing Logs

```bash
# Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# PHP-FPM logs
sudo tail -f /var/log/php-fpm.log

# System logs
sudo journalctl -u nginx -f
sudo journalctl -u php-fpm -f
```

## Troubleshooting

### Installation Fails

1. **Check pre-flight requirements:**
   ```bash
   hostarchy check
   ```

2. **Verify mounts (for performance/database profiles):**
   ```bash
   mount | grep -E "(/srv|/db)"
   ```

3. **Check internet connectivity:**
   ```bash
   ping -c 3 archlinux.org
   ```

4. **Review installation logs:**
   ```bash
   journalctl -xe
   ```

### Services Not Starting

1. **Check service status:**
   ```bash
   systemctl status SERVICE_NAME
   ```

2. **Check configuration:**
   ```bash
   # Nginx
   sudo nginx -t
   
   # PHP-FPM
   sudo php-fpm -t
   
   # SSH
   sudo sshd -t
   ```

3. **Check logs:**
   ```bash
   sudo journalctl -u SERVICE_NAME -n 50
   ```

### Configuration Not Applied

1. **Re-apply configuration:**
   ```bash
   sudo hostarchy apply
   ```

2. **Check state file:**
   ```bash
   cat /etc/hostarchy/state/installed
   ```

3. **Verify profile:**
   ```bash
   hostarchy profile
   ```

### Pacman Hook Not Working

1. **Check hook file:**
   ```bash
   cat /etc/pacman.d/hooks/hostarchy.hook
   ```

2. **Verify hook is installed:**
   ```bash
   ls -la /etc/pacman.d/hooks/
   ```

3. **Test manually:**
   ```bash
   sudo hostarchy apply
   ```

## Uninstallation

To remove HostArchy (not recommended, but possible):

```bash
# Stop services
sudo systemctl stop nginx php-fpm mariadb postgresql redis fail2ban

# Remove packages (optional - be careful!)
# sudo pacman -Rs nginx php php-fpm mariadb postgresql redis fail2ban

# Remove HostArchy files
sudo rm -rf /usr/local/hostarchy
sudo rm -rf /etc/hostarchy
sudo rm /usr/local/bin/hostarchy
sudo rm /etc/pacman.d/hooks/hostarchy.hook

# Remove configuration files (backup first!)
# sudo rm /etc/sysctl.d/99-hostarchy.conf
# sudo rm /etc/fail2ban/jail.local
# etc.
```

**Note:** Back up your data and configurations before uninstalling!

## Next Steps

- Configure your websites in `/srv/http/`
- Set up SSL/TLS certificates (consider using Certbot)
- Configure database users and permissions
- Set up backups for `/srv/backups/`
- Configure monitoring and alerting
- Review security hardening options

## Additional Resources

- [README.md](README.md) - Technical specification
- [QUICKSTART.md](QUICKSTART.md) - Quick reference
- [ARCHGUIDE.md](ARCHGUIDE.md) - Arch Linux installation guide
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) - Project structure documentation

