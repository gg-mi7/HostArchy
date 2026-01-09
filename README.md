# 🏴 HostArchy – Technical Specification v1.1

**Arch-based performance & web-hosting system layer**

This document provides a detailed, structured specification for HostArchy, a system layer applied on vanilla Arch Linux to create a high-performance web hosting environment.

---

## 0️⃣ Definition & Scope

HostArchy transforms a general-purpose Arch Linux into a **specialized hosting environment**.

**IS NOT:** a Linux distribution, kernel fork, or package manager.

**IS:** an idempotent configuration engine, system tuner, and structured filesystem standard.

---

## 1️⃣ Requirements & Partitioning

### 1.1 Partition Layout Strategy

HostArchy separates OS, data, and logs to prevent I/O contention.

#### Bare Metal / Custom VM (Strict Mode)

Required for "Performance" and "Database" profiles.

| Mount Point | Filesystem | Purpose                                  |
| ----------- | ---------- | ---------------------------------------- |
| /boot       | FAT32      | UEFI Boot                                |
| /           | ext4       | Base System                              |
| /srv        | XFS        | Web content, git repos, static assets    |
| /db         | XFS        | Databases (Postgres/MariaDB), Redis dump |

#### Cloud VPS (Compatibility Mode)

Allowed for "Balanced" or "General Hosting" profiles.

- Single partition detected by installer.
- Bind mounts or Btrfs subvolumes simulate /srv and /db.
- User must accept "No Physical Isolation" warning.

---

## 2️⃣ Base Arch Installation

Required packages:

```bash
pacstrap /mnt base linux linux-firmware systemd-sysvcompat grub efibootmgr git base-devel openssh neovim htop rsync
```

**Network stack:** systemd-networkd + systemd-resolved (NetworkManager removed for latency/stability reasons).

---

## 3️⃣ Directory Structure

HostArchy-managed paths:

**Configuration & Core**

```
/etc/hostarchy/
├─ config/    # Global env variables
├─ profiles/  # Active profile definitions
├─ state/     # Current applied state checksums
└─ hooks/     # User scripts post-update
```

**Data**

```
/srv/
├─ http/     # Public web roots
├─ git/      # Bare git repos
└─ backups/  # Local snapshots

/db/
├─ mariadb/
├─ postgres/
├─ redis/
└─ metadata/ # DB tracking info
```

**Binaries**

```
/usr/local/hostarchy/
├─ bin/       # CLI tools
├─ lib/       # Python/Bash libraries
└─ templates/ # Config templates
```

---

## 4️⃣ Installation Flow

### 4.1 Bootstrap

```bash
git clone https://github.com/hostarchy/hostarchy.git /usr/local/hostarchy
cd /usr/local/hostarchy
chmod +x install.sh
./install.sh --profile=hosting
```

### 4.2 install.sh Logic

- Idempotent: running twice ensures state correctness.
- Pre-flight checks: Arch Linux, /db mount, internet.
- Profile selection: hosting, performance, database.
- Stack selection: nginx, PHP 8.x, MariaDB/Postgres.
- Execution: symlink hostarchy binary, apply sysctl, enable systemd services.

---

## 5️⃣ System Tuning & Modifications

**Kernel & sysctl:**

- Applied via /etc/sysctl.d/99-hostarchy.conf
- TCP BBR, net.core.somaxconn, TCP TW socket reuse
- vm.swappiness=10, vm.dirty\_ratio increased
- kptr\_restrict enabled, dmesg restricted

**Service Hardening:**

- SSH: custom port, PermitRootLogin prohibit-password, PasswordAuthentication no
- Fail2Ban: SSH/Nginx jails
- Firewall: nftables, default DROP

---

## 6️⃣ Web Stack

**Nginx:** minimal /etc/nginx/nginx.conf, sites-available symlinked to sites-enabled, gzip, sendfile, fd cache enabled.

**PHP-FPM:** Unix socket communication, JIT enabled on supported CPUs.

---

## 7️⃣ Persistence & Updates

Arch rolling updates may overwrite configs.

- Pacman hook: /etc/pacman.d/hooks/hostarchy.hook
- Re-applies HostArchy optimizations after nginx, php\*, linux updates.

---

## 8️⃣ Future-Proofing & Extensions

- JSON output for monitoring: `hostarchy status --json`
- Ansible compatibility: exports variables for automation
- Rollback (optional Btrfs snapshots) before upgrades

---

**End of HostArchy Technical Specification v1.1**

This is a full blueprint for automated implementation, system tuning, and future extensions.

