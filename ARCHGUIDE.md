# Arch Linux Installation Guide for HostArchy

This guide walks you through setting up a vanilla Arch Linux installation that is ready for HostArchy.

## Prerequisites

- Bootable USB drive with Arch Linux ISO
- Internet connection
- At least 20GB of disk space (recommended: 40GB+)
- UEFI-compatible system (recommended for HostArchy performance profiles)

## Installation Steps

### 1. Boot from Arch ISO

1. Download the latest Arch Linux ISO from [archlinux.org](https://archlinux.org/download/)
2. Create a bootable USB drive
3. Boot from the USB and select "Boot Arch Linux (x86_64)"

### 2. Verify Boot Mode

Check if the system is booted in UEFI mode:

```bash
ls /sys/firmware/efi/efivars
```

If this directory exists, you're in UEFI mode. If not, you're in BIOS mode (legacy).

### 3. Connect to the Internet

**Wired connection (automatic):**
```bash
# Usually works automatically with systemd-networkd
ip link
ping -c 3 archlinux.org
```

**Wi-Fi connection:**
```bash
# List available networks
iwctl device list
iwctl station wlan0 scan
iwctl station wlan0 get-networks
iwctl station wlan0 connect SSID

# Enter password when prompted, then verify connection
ping -c 3 archlinux.org
```

### 4. Update System Clock

```bash
timedatectl set-ntp true
```

### 5. Partition the Disk

**IMPORTANT:** HostArchy requires specific partition layouts for optimal performance.

#### For Performance/Database Profiles (Recommended)

HostArchy requires separate partitions for `/srv` and `/db` for these profiles.

```bash
# List available disks
lsblk

# For this example, we assume /dev/sda
# Replace with your actual disk device

# Start partitioning (using parted for GPT)
parted /dev/sda mklabel gpt

# Create partitions:
# 1. EFI Boot partition (512MB, FAT32)
parted /dev/sda mkpart primary fat32 1MiB 513MiB
parted /dev/sda set 1 esp on

# 2. Root partition (20GB, ext4)
parted /dev/sda mkpart primary ext4 513MiB 20.5GiB

# 3. /srv partition (remaining space, XFS)
parted /dev/sda mkpart primary xfs 20.5GiB 60%

# 4. /db partition (remaining space, XFS)
parted /dev/sda mkpart primary xfs 60% 100%

# Verify partitions
parted /dev/sda print
```

#### For Hosting Profile (Compatibility Mode)

If you're using the hosting profile on a VPS with single partition, you can use a simpler layout:

```bash
# Single partition layout
parted /dev/sda mklabel gpt
parted /dev/sda mkpart primary fat32 1MiB 513MiB
parted /dev/sda set 1 esp on
parted /dev/sda mkpart primary ext4 513MiB 100%
```

**Note:** In compatibility mode, HostArchy will create bind mounts for `/srv` and `/db`.

### 6. Format Partitions

#### For Performance/Database Profiles:

```bash
# Format EFI boot partition
mkfs.fat -F32 /dev/sda1

# Format root partition
mkfs.ext4 /dev/sda2

# Format /srv partition (XFS)
mkfs.xfs /dev/sda3

# Format /db partition (XFS)
mkfs.xfs /dev/sda4
```

#### For Hosting Profile (Compatibility Mode):

```bash
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2
```

### 7. Mount Partitions

#### For Performance/Database Profiles:

```bash
# Mount root
mount /dev/sda2 /mnt

# Create mount points
mkdir -p /mnt/boot /mnt/srv /mnt/db

# Mount EFI boot
mount /dev/sda1 /mnt/boot

# Mount /srv
mount /dev/sda3 /mnt/srv

# Mount /db
mount /dev/sda4 /mnt/db
```

#### For Hosting Profile (Compatibility Mode):

```bash
mount /dev/sda2 /mnt
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot
```

### 8. Install Base System

Install the base Arch Linux packages required by HostArchy:

```bash
pacstrap /mnt base linux linux-firmware systemd-sysvcompat grub efibootmgr git base-devel openssh neovim htop rsync
```

**Important:** Do NOT install NetworkManager or other network managers. HostArchy uses `systemd-networkd` and `systemd-resolved`.

### 9. Generate fstab

```bash
genfstab -U /mnt >> /mnt/etc/fstab

# Verify fstab
cat /mnt/etc/fstab
```

### 10. Chroot into New System

```bash
arch-chroot /mnt
```

### 11. Set Time Zone

```bash
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
# Example: ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

hwclock --systohc
```

### 12. Localization

Edit `/etc/locale.gen` and uncomment desired locales (e.g., `en_US.UTF-8 UTF-8`):

```bash
nano /etc/locale.gen
```

Generate locales:

```bash
locale-gen
```

Create `/etc/locale.conf`:

```bash
echo "LANG=en_US.UTF-8" > /etc/locale.conf
```

### 13. Network Configuration

Create hostname file:

```bash
echo "hostname" > /etc/hostname
# Replace "hostname" with your desired hostname
```

Add entry to `/etc/hosts`:

```bash
cat >> /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   hostname.localdomain  hostname
EOF
```

### 14. Configure systemd-networkd

HostArchy uses systemd-networkd instead of NetworkManager.

**For wired connection:**

Create `/etc/systemd/network/20-wired.network`:

```bash
cat > /etc/systemd/network/20-wired.network <<EOF
[Match]
Name=en*

[Network]
DHCP=yes
EOF
```

**For wireless connection:**

Install `iwd` and `wpa_supplicant`:

```bash
pacman -Sy iwd wpa_supplicant
systemctl enable iwd
systemctl enable systemd-networkd
systemctl enable systemd-resolved
```

### 15. Set Root Password

```bash
passwd
```

### 16. Install Boot Loader (GRUB)

```bash
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
```

For BIOS systems (legacy):

```bash
grub-install --target=i386-pc /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg
```

### 17. Enable systemd Services

```bash
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable sshd
```

### 18. Exit and Reboot

```bash
exit
umount -R /mnt
reboot
```

### 19. Post-Installation Verification

After reboot, log in as root and verify:

```bash
# Check network
ping -c 3 archlinux.org

# Check mounts (for performance/database profiles)
mount | grep -E "(srv|db)"

# Check disk space
df -h

# Verify systemd services
systemctl status systemd-networkd
systemctl status systemd-resolved
```

### 20. Update System

```bash
pacman -Syu
```

## Next Steps

Once vanilla Arch Linux is installed and verified, proceed to [HOSTARCHY.md](HOSTARCHY.md) for HostArchy installation.

## Troubleshooting

### Network Not Working After Reboot

1. Check service status:
   ```bash
   systemctl status systemd-networkd
   ```

2. Enable and start services:
   ```bash
   systemctl enable systemd-networkd
   systemctl enable systemd-resolved
   systemctl start systemd-networkd
   systemctl start systemd-resolved
   ```

### Partitions Not Mounting

1. Check fstab:
   ```bash
   cat /etc/fstab
   ```

2. Verify UUIDs:
   ```bash
   blkid
   ```

3. Manually mount and test before adding to fstab.

### Boot Loader Issues

For UEFI systems, ensure:
- ESP partition is mounted at `/boot`
- Secure Boot is disabled (or configure properly)
- UEFI firmware is set to boot from the correct device

## Notes

- **Performance/Database Profiles**: Require separate `/srv` and `/db` partitions for optimal performance
- **Hosting Profile**: Can work with single partition using compatibility mode
- **Network Manager**: Do NOT install NetworkManager - HostArchy uses systemd-networkd
- **Swap**: You may want to create a swap partition/file after basic installation (not required for HostArchy)

## Additional Resources

- [Arch Linux Installation Guide](https://wiki.archlinux.org/title/Installation_guide)
- [systemd-networkd Documentation](https://wiki.archlinux.org/title/Systemd-networkd)
- [Partitioning Guide](https://wiki.archlinux.org/title/Partitioning)

