# HostArchy Quick Start Guide

**For detailed installation instructions, see:**
- [ARCHGUIDE.md](ARCHGUIDE.md) - How to set up vanilla Arch Linux
- [HOSTARCHY.md](HOSTARCHY.md) - How to install and configure HostArchy

## Installation

1. **Prerequisites**: You must be running Arch Linux (or an Arch-based distribution)

   **If you don't have Arch Linux installed yet**, follow [ARCHGUIDE.md](ARCHGUIDE.md) first.

2. **Clone the repository**:
```bash
git clone https://github.com/hostarchy/hostarchy.git /usr/local/hostarchy
cd /usr/local/hostarchy
```

   **For detailed HostArchy installation instructions**, see [HOSTARCHY.md](HOSTARCHY.md).

3. **Run the installer**:
```bash
chmod +x install.sh
sudo ./install.sh --profile=hosting
```

Available profiles:
- `hosting` - General-purpose web hosting (allows compatibility mode)
- `performance` - High-performance hosting (requires /db mount)
- `database` - Database server only (requires /db mount)

## Basic Usage

After installation, use the `hostarchy` CLI tool:

```bash
# Check status
hostarchy status

# Check status (JSON output)
hostarchy status --json

# View current profile
hostarchy profile

# Change profile
hostarchy profile --profile=performance

# Run pre-flight checks
hostarchy check

# Re-apply configuration (after manual changes)
hostarchy apply

# Show version
hostarchy version
```

## Directory Structure

After installation:

- `/etc/hostarchy/` - Configuration and state
- `/usr/local/hostarchy/` - Installed files
- `/srv/http/` - Web root
- `/srv/git/` - Git repositories
- `/srv/backups/` - Backups
- `/db/` - Database data (if mounted)

## Profiles

### Hosting Profile
- Nginx web server
- PHP-FPM with OPcache
- Optional databases
- Balanced optimization
- Allows compatibility mode (single partition)

### Performance Profile
- Optimized Nginx
- PHP-FPM with JIT enabled
- MariaDB, PostgreSQL, Redis
- Aggressive optimization
- Requires separate /db mount

### Database Profile
- Specialized database server
- MariaDB, PostgreSQL, Redis
- Database-focused optimizations
- Requires separate /db mount

## Configuration Files

- `/etc/sysctl.d/99-hostarchy.conf` - System tuning
- `/etc/nginx/nginx.conf` - Nginx configuration
- `/etc/php/php-fpm.d/www.conf` - PHP-FPM configuration
- `/etc/fail2ban/jail.local` - Fail2Ban configuration
- `/etc/nftables.conf` - Firewall rules

## Troubleshooting

If services fail to start:
```bash
# Check service status
systemctl status nginx
systemctl status php-fpm

# Check logs
journalctl -u nginx -f
journalctl -u php-fpm -f

# Re-apply configuration
hostarchy apply
```

For more information:
- [README.md](README.md) - Technical specification
- [ARCHGUIDE.md](ARCHGUIDE.md) - Arch Linux installation guide
- [HOSTARCHY.md](HOSTARCHY.md) - HostArchy installation guide
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) - Project structure

