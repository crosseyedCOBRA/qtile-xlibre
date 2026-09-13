#!/usr/bin/env bash

#

# Artix Linux + XLibre + dwm installer

# UEFI / OpenRC / XFS / LightDM / PipeWire / ConnMan / Flatpak

#

# Default target: /dev/nvme0n1

# Default user:   mike

#

# WARNING: THIS SCRIPT ERASES THE SELECTED DISK.

#

set -Eeuo pipefail

###############################################################################

# Configuration

###############################################################################

TARGET_DISK="/dev/nvme0n1"

EFI_PART="${TARGET_DISK}p1"
ROOT_PART="${TARGET_DISK}p2"

MNT="/mnt"

DEFAULT_HOSTNAME="artix"
DEFAULT_USERNAME="mike"
DEFAULT_TIMEZONE="America/New_York"
DEFAULT_KEYMAP="us"
DEFAULT_LOCALE="en_US.UTF-8"

###############################################################################

# Helpers

###############################################################################

log() {
echo
echo "==> $*"
}

fail() {
echo
echo "============================================================"
echo "ERROR: $*"
echo "============================================================"
exit 1
}

cleanup_on_error() {
echo
echo "============================================================"
echo "INSTALLATION FAILED"
echo "============================================================"
echo
echo "The target system may be partially installed."
echo
}

trap cleanup_on_error ERR

###############################################################################

# Initial checks

###############################################################################

[[ "$EUID" -eq 0 ]] || fail "Run this installer as root."

[[ -b "$TARGET_DISK" ]] || 
fail "Target disk $TARGET_DISK does not exist."

if [[ ! -d /sys/firmware/efi ]]; then
fail "This system is not booted in UEFI mode. Reboot the live ISO in UEFI mode."
fi

###############################################################################

# Network check

###############################################################################

log "Checking network connectivity..."

if ! ping -c 1 -W 3 artixlinux.org >/dev/null 2>&1; then
fail "Network connectivity check failed."
fi

###############################################################################

# User configuration

###############################################################################

echo
echo "============================================================"
echo "SYSTEM CONFIGURATION"
echo "============================================================"
echo

read -r -p "Hostname [$DEFAULT_HOSTNAME]: " HOSTNAME
HOSTNAME="${HOSTNAME:-$DEFAULT_HOSTNAME}"

read -r -p "Username [$DEFAULT_USERNAME]: " USERNAME
USERNAME="${USERNAME:-$DEFAULT_USERNAME}"

read -r -p "Timezone [$DEFAULT_TIMEZONE]: " TIMEZONE
TIMEZONE="${TIMEZONE:-$DEFAULT_TIMEZONE}"

read -r -p "Keyboard layout [$DEFAULT_KEYMAP]: " KEYMAP
KEYMAP="${KEYMAP:-$DEFAULT_KEYMAP}"

read -r -p "Locale [$DEFAULT_LOCALE]: " LOCALE
LOCALE="${LOCALE:-$DEFAULT_LOCALE}"

###############################################################################

# Validate username

###############################################################################

if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
fail "Invalid username: $USERNAME"
fi

###############################################################################

# Collect user password

#

# This happens before the disk is touched.

###############################################################################

echo
echo "============================================================"
echo "USER PASSWORD"
echo "============================================================"
echo
echo "Set the password for '$USERNAME'."
echo
echo "This is the password you will use with sudo."
echo
echo "There is NO separate root password."
echo "The root account will remain locked."
echo

while true; do

```
read -r -s -p "Password: " USER_PASSWORD
echo

if [[ -z "$USER_PASSWORD" ]]; then
    echo "Password cannot be empty."
    echo
    continue
fi

read -r -s -p "Confirm password: " USER_PASSWORD_CONFIRM
echo

if [[ "$USER_PASSWORD" == "$USER_PASSWORD_CONFIRM" ]]; then
    unset USER_PASSWORD_CONFIRM
    break
fi

echo
echo "Passwords do not match. Try again."
echo
```

done

###############################################################################

# Disk confirmation

###############################################################################

echo
echo "============================================================"
echo "FINAL DISK CONFIRMATION"
echo "============================================================"
echo
echo "THE FOLLOWING DISK WILL BE COMPLETELY ERASED:"
echo
echo "    $TARGET_DISK"
echo
echo "Partition layout:"
echo "    ${EFI_PART}  - 512 MiB EFI System Partition"
echo "    ${ROOT_PART} - Remaining space, XFS"
echo
echo "Filesystem:"
echo "    EFI  -> FAT32"
echo "    Root -> XFS"
echo
echo "System:"
echo "    Artix Linux"
echo "    OpenRC"
echo "    XLibre"
echo "    dwm"
echo "    LightDM"
echo
echo "User:"
echo "    $USERNAME"
echo
echo "Root account:"
echo "    LOCKED"
echo
echo "============================================================"
echo

read -r -p "Type ERASE to continue: " CONFIRM

[[ "$CONFIRM" == "ERASE" ]] || 
fail "Installation cancelled."

###############################################################################

# Live environment prerequisites

###############################################################################

log "Installing live-environment disk tools..."

pacman -Sy --needed --noconfirm 
gptfdisk 
parted

command -v sgdisk >/dev/null 2>&1 || 
fail "sgdisk is unavailable."

command -v partprobe >/dev/null 2>&1 || 
fail "partprobe is unavailable."

command -v basestrap >/dev/null 2>&1 || 
fail "basestrap is unavailable in this Artix live environment."

###############################################################################

# Unmount existing target

###############################################################################

log "Unmounting existing target mounts..."

umount -R "$MNT" 2>/dev/null || true
swapoff -a 2>/dev/null || true

###############################################################################

# Partition disk

###############################################################################

log "Wiping existing partition table..."

wipefs -af "$TARGET_DISK"

sgdisk --zap-all "$TARGET_DISK"
sgdisk --clear "$TARGET_DISK"

log "Creating GPT partition table..."

sgdisk 
--new=1:1MiB:+512MiB 
--typecode=1:ef00 
"$TARGET_DISK"

sgdisk 
--new=2:0:0 
--typecode=2:8300 
"$TARGET_DISK"

partprobe "$TARGET_DISK"

sleep 2

[[ -b "$EFI_PART" ]] || 
fail "EFI partition $EFI_PART was not created."

[[ -b "$ROOT_PART" ]] || 
fail "Root partition $ROOT_PART was not created."

###############################################################################

# Filesystems

###############################################################################

log "Creating FAT32 EFI filesystem..."

mkfs.fat -F32 "$EFI_PART"

log "Creating XFS root filesystem..."

mkfs.xfs -f "$ROOT_PART"

###############################################################################

# Mount filesystems

###############################################################################

log "Mounting root filesystem..."

mount "$ROOT_PART" "$MNT"

mkdir -p "$MNT/boot/efi"

log "Mounting EFI partition..."

mount "$EFI_PART" "$MNT/boot/efi"

###############################################################################

# Install base Artix system

###############################################################################

log "Installing base Artix system..."

basestrap 
"$MNT" 
base 
base-devel 
linux 
linux-firmware 
amd-ucode 
openrc 
elogind 
elogind-openrc 
dbus 
dbus-openrc 
xfsprogs 
grub 
efibootmgr 
connman 
connman-openrc 
sudo 
curl 
wget 
nano 
git

###############################################################################

# Generate fstab

###############################################################################

log "Generating fstab..."

fstabgen -U "$MNT" > "$MNT/etc/fstab"

###############################################################################

# Store configuration for chroot

###############################################################################

cat > "$MNT/root/install-vars" <<EOF
HOSTNAME=$(printf '%q' "$HOSTNAME")
USERNAME=$(printf '%q' "$USERNAME")
TIMEZONE=$(printf '%q' "$TIMEZONE")
KEYMAP=$(printf '%q' "$KEYMAP")
LOCALE=$(printf '%q' "$LOCALE")
EOF

###############################################################################

# Store user password

#

# Only root can read this file.

###############################################################################

printf '%s' "$USER_PASSWORD" > "$MNT/root/user-password"

chmod 600 "$MNT/root/user-password"

unset USER_PASSWORD

###############################################################################

# Create target-system installation script

###############################################################################

log "Preparing target-system configuration..."

cat > "$MNT/root/install-chroot.sh" <<'CHROOT'
#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################

# Load variables

###############################################################################

source /root/install-vars

USER_PASSWORD_FILE="/root/user-password"

###############################################################################

# Helpers

###############################################################################

log() {
echo
echo "==> $*"
}

fail() {
echo
echo "============================================================"
echo "CHROOT ERROR: $*"
echo "============================================================"
exit 1
}

###############################################################################

# Verify password file

###############################################################################

[[ -f "$USER_PASSWORD_FILE" ]] || 
fail "User password file is missing."

###############################################################################

# Timezone

###############################################################################

log "Configuring timezone..."

[[ -e "/usr/share/zoneinfo/${TIMEZONE}" ]] || 
fail "Timezone does not exist: ${TIMEZONE}"

ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime

hwclock --systohc

################################################################
