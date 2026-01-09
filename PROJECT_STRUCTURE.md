# HostArchy Project Structure

This document describes the complete structure of the HostArchy project.

## Root Directory

- `README.md` - Technical specification (v1.1)
- `install.sh` - Main installation script (idempotent)
- `QUICKSTART.md` - Quick start guide
- `CONTRIBUTING.md` - Contribution guidelines
- `.gitignore` - Git ignore rules
- `PROJECT_STRUCTURE.md` - This file

## Directories

### `/bin/`
Contains the main CLI tool:
- `hostarchy` - Main CLI tool with commands:
  - `status` - Show current HostArchy status
  - `status --json` - Show status in JSON format
  - `profile` - Show or set active profile
  - `check` - Run pre-flight checks
  - `apply` - Re-apply HostArchy configuration
  - `version` - Show version information

### `/lib/`
Library scripts with shared functionality:
- `common.sh` - Common functions (logging, file operations, sysctl, services)
- `system-tuning.sh` - System tuning and kernel optimizations
- `service-config.sh` - Service configuration (nginx, PHP-FPM, databases, SSH, fail2ban, firewall)

### `/profiles/`
Profile definitions:
- `hosting.sh` - General-purpose web hosting profile
- `performance.sh` - High-performance web hosting profile
- `database.sh` - Database server profile

### `/templates/`
Configuration templates:
- `nginx-site.conf` - Nginx site template
- `php-site.ini` - PHP configuration template
- `mariadb-optimized.cnf` - MariaDB optimization template
- `postgresql-optimized.conf` - PostgreSQL optimization template

### `/pacman-hooks/`
Pacman hooks for automatic re-application:
- `hostarchy.hook` - Triggers `hostarchy apply` after package updates

## Installation Flow

1. User runs `./install.sh --profile=PROFILE`
2. Pre-flight checks (Arch Linux, mounts, internet)
3. Directory structure creation
4. File copying to `/usr/local/hostarchy/`
5. Package installation
6. Profile application
7. System tuning application
8. Service configuration
9. Pacman hook installation
10. State saving

## Runtime Structure (After Installation)

```
/etc/hostarchy/
├─ config/    # Global env variables
├─ profiles/  # Active profile definitions
├─ state/     # Current applied state checksums
└─ hooks/     # User scripts post-update

/usr/local/hostarchy/
├─ bin/       # CLI tools (hostarchy)
├─ lib/       # Bash libraries
└─ templates/ # Config templates

/srv/
├─ http/     # Public web roots
├─ git/      # Bare git repos
└─ backups/  # Local snapshots

/db/
├─ mariadb/
├─ postgres/
├─ redis/
└─ metadata/
```

## Configuration Files Created

- `/etc/sysctl.d/99-hostarchy.conf` - System tuning
- `/etc/nginx/nginx.conf` - Nginx configuration
- `/etc/php/php-fpm.d/www.conf` - PHP-FPM configuration
- `/etc/fail2ban/jail.local` - Fail2Ban configuration
- `/etc/nftables.conf` - Firewall rules
- `/etc/pacman.d/hooks/hostarchy.hook` - Pacman hook

## Features

- **Idempotent**: Can be run multiple times safely
- **Profile-based**: Different configurations for different use cases
- **Compatibility mode**: Works on single partition VPS
- **Automatic re-application**: Pacman hooks maintain configuration
- **CLI tool**: Easy management via `hostarchy` command
- **JSON output**: For monitoring and automation

