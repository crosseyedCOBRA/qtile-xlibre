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

[[ -b "$TARGET_DISK" ]] || \
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

[[ "$CONFIRM" == "ERASE" ]] || \
    fail "Installation cancelled."

###############################################################################
# Live environment prerequisites
###############################################################################

log "Installing live-environment disk tools..."

pacman -Sy --needed --noconfirm \
    gptfdisk \
    parted

command -v sgdisk >/dev/null 2>&1 || \
    fail "sgdisk is unavailable."

command -v partprobe >/dev/null 2>&1 || \
    fail "partprobe is unavailable."

command -v basestrap >/dev/null 2>&1 || \
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

sgdisk \
    --new=1:1MiB:+512MiB \
    --typecode=1:ef00 \
    "$TARGET_DISK"

sgdisk \
    --new=2:0:0 \
    --typecode=2:8300 \
    "$TARGET_DISK"

partprobe "$TARGET_DISK"

sleep 2

[[ -b "$EFI_PART" ]] || \
    fail "EFI partition $EFI_PART was not created."

[[ -b "$ROOT_PART" ]] || \
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

basestrap \
    "$MNT" \
    base \
    base-devel \
    linux \
    linux-firmware \
    amd-ucode \
    openrc \
    elogind \
    elogind-openrc \
    dbus \
    dbus-openrc \
    xfsprogs \
    grub \
    efibootmgr \
    connman \
    connman-openrc \
    sudo \
    curl \
    wget \
    nano \
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

[[ -f "$USER_PASSWORD_FILE" ]] || \
    fail "User password file is missing."

###############################################################################
# Timezone
###############################################################################

log "Configuring timezone..."

[[ -e "/usr/share/zoneinfo/${TIMEZONE}" ]] || \
    fail "Timezone does not exist: ${TIMEZONE}"

ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime

hwclock --systohc

###############################################################################
# Locale
###############################################################################

log "Configuring locale..."

if grep -q "^#${LOCALE} UTF-8" /etc/locale.gen; then
    sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen
elif ! grep -q "^${LOCALE} UTF-8" /etc/locale.gen; then
    echo "${LOCALE} UTF-8" >> /etc/locale.gen
fi

locale-gen

cat > /etc/locale.conf <<EOF
LANG=${LOCALE}
EOF

###############################################################################
# Keyboard
###############################################################################

cat > /etc/vconsole.conf <<EOF
KEYMAP=${KEYMAP}
EOF

###############################################################################
# Hostname
###############################################################################

log "Configuring hostname..."

echo "${HOSTNAME}" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

###############################################################################
# XLibre Artix repository
###############################################################################

log "Configuring Artix XLibre repository..."

cd /root

curl -fLO https://xlibre-artix.github.io/xlibre-artixlinux.asc

pacman-key --add xlibre-artixlinux.asc

pacman-key --lsign-key 2AFFCD7B42ADD2E7

if ! grep -q '^\[xlibre-stable\]' /etc/pacman.conf; then

    awk '
        /^\[world\]/ && !inserted {
            print "[xlibre-stable]"
            print "Server = https://github.com/xlibre-artix/stable/releases/download/$arch"
            print ""
            inserted=1
        }
        { print }
    ' /etc/pacman.conf > /etc/pacman.conf.new

    mv /etc/pacman.conf.new /etc/pacman.conf

fi

###############################################################################
# Arch Linux repository support
###############################################################################

log "Configuring Arch Linux repository support..."

if ! grep -q '^\[universe\]' /etc/pacman.conf; then

    cat >> /etc/pacman.conf <<'EOFUNIVERSE'

[universe]
Server = https://universe.artixlinux.org/$arch
Server = https://mirror1.artixlinux.org/universe/$arch
Server = https://mirror.pascalpuffke.de/artix-universe/$arch
EOFUNIVERSE

fi

pacman -Sy --needed --noconfirm \
    artix-archlinux-support

pacman-key --populate artix
pacman-key --populate archlinux

if ! grep -q '^\[extra\]' /etc/pacman.conf; then

    cat >> /etc/pacman.conf <<'EOFARCH'

# Arch Linux repository
[extra]
Include = /etc/pacman.d/mirrorlist-arch
EOFARCH

fi

[[ -s /etc/pacman.d/mirrorlist-arch ]] || \
    fail "/etc/pacman.d/mirrorlist-arch does not exist."

###############################################################################
# Refresh package databases
###############################################################################

log "Refreshing package databases..."

pacman -Syy

###############################################################################
# Required package preflight
###############################################################################

log "Checking required packages..."

REQUIRED_PACKAGES=(
    xlibre-meta
    xlibre-video-amdgpu
    dwm
    lightdm
    lightdm-gtk-greeter
    lightdm-openrc
    connman
    connman-openrc
)

for pkg in "${REQUIRED_PACKAGES[@]}"; do

    if ! pacman -Si "$pkg" >/dev/null 2>&1; then
        fail "Required package '${pkg}' is unavailable."
    fi

done

###############################################################################
# System update
###############################################################################

log "Updating base system..."

pacman -Su --noconfirm

###############################################################################
# XLibre
###############################################################################

log "Installing XLibre..."

pacman -S --needed --noconfirm \
    xlibre-meta \
    xlibre-video-amdgpu \
    xorg-xdpyinfo \
    xorg-xrandr \
    xorg-xset \
    xorg-xsetroot \
    xorg-xmodmap \
    xorg-xev \
    xorg-xprop \
    xclip

###############################################################################
# dwm / LightDM / desktop utilities
###############################################################################

log "Installing dwm and desktop components..."

pacman -S --needed --noconfirm \
    dwm \
    alacritty \
    lightdm \
    lightdm-gtk-greeter \
    lightdm-openrc \
    rofi \
    dunst \
    picom \
    feh \
    thunar \
    pavucontrol \
    flameshot

###############################################################################
# PipeWire
###############################################################################

log "Installing PipeWire..."

pacman -S --needed --noconfirm \
    pipewire \
    pipewire-audio \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    rtkit

###############################################################################
# Networking / Bluetooth
###############################################################################

log "Installing networking and Bluetooth..."

pacman -S --needed --noconfirm \
    connman \
    connman-openrc \
    bluez \
    bluez-utils \
    blueman

###############################################################################
# Flatpak
###############################################################################

log "Installing Flatpak..."

pacman -S --needed --noconfirm \
    flatpak \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk

###############################################################################
# Fonts / utilities / development tools
###############################################################################

log "Installing fonts and utilities..."

pacman -S --needed --noconfirm \
    noto-fonts \
    noto-fonts-emoji \
    ttf-dejavu \
    ttf-liberation \
    ttf-jetbrains-mono \
    fastfetch \
    btop \
    unzip \
    zip \
    p7zip \
    gcc \
    make \
    cmake \
    pkgconf

###############################################################################
# Create user
###############################################################################

log "Creating user '${USERNAME}'..."

if id "${USERNAME}" >/dev/null 2>&1; then
    log "User '${USERNAME}' already exists."
else
    useradd \
        -m \
        -G wheel,audio,video \
        -s /bin/bash \
        "${USERNAME}"
fi

###############################################################################
# Apply user password
###############################################################################

log "Setting password for '${USERNAME}'..."

[[ -s "$USER_PASSWORD_FILE" ]] || \
    fail "User password file is empty."

USER_PASSWORD="$(cat "$USER_PASSWORD_FILE")"

printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | chpasswd

unset USER_PASSWORD

###############################################################################
# Immediately delete password file
###############################################################################

rm -f "$USER_PASSWORD_FILE"

###############################################################################
# Sudo configuration
###############################################################################

log "Configuring sudo..."

cat > /etc/sudoers.d/10-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 440 /etc/sudoers.d/10-wheel

visudo -cf /etc/sudoers.d/10-wheel >/dev/null || \
    fail "sudoers configuration is invalid."

###############################################################################
# Lock root
###############################################################################

log "Locking root account..."

passwd -l root

###############################################################################
# dwm XSession
###############################################################################

log "Creating dwm desktop session..."

mkdir -p /usr/share/xsessions

cat > /usr/share/xsessions/dwm.desktop <<'EOF'
[Desktop Entry]
Name=dwm
Comment=Dynamic Window Manager
Exec=dwm
Type=Application
DesktopNames=dwm
EOF

###############################################################################
# LightDM
###############################################################################

log "Configuring LightDM..."

cat > /etc/lightdm/lightdm.conf <<'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=dwm
EOF

###############################################################################
# OpenRC services
###############################################################################

log "Enabling OpenRC services..."

rc-update add connmand default || true
rc-update add elogind boot || true
rc-update add dbus default || true
rc-update add lightdm default || true

if [[ -x /etc/init.d/bluetooth ]]; then
    rc-update add bluetooth default || true
fi

###############################################################################
# GRUB
###############################################################################

log "Installing GRUB..."

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=Artix \
    --recheck

###############################################################################
# Initramfs
###############################################################################

log "Generating initramfs..."

mkinitcpio -P

###############################################################################
# GRUB configuration
###############################################################################

log "Generating GRUB configuration..."

grub-mkconfig -o /boot/grub/grub.cfg

###############################################################################
# XLibre verification helper
###############################################################################

log "Creating XLibre verification helper..."

cat > /usr/local/bin/check-xlibre <<'EOF'
#!/usr/bin/env bash

echo "Display server information:"
echo

if command -v xdpyinfo >/dev/null 2>&1; then
    xdpyinfo | grep -E "vendor string|vendor release"
else
    echo "xdpyinfo is not installed."
fi

echo
echo "Installed XLibre packages:"
pacman -Q | grep -i xlibre || true

echo
echo "XLibre AMD driver:"
pacman -Q xlibre-video-amdgpu 2>/dev/null || true
EOF

chmod +x /usr/local/bin/check-xlibre

###############################################################################
# Final verification
###############################################################################

log "Running final checks..."

echo
echo "============================================================"
echo "USER"
echo "============================================================"
id "${USERNAME}"

echo
echo "============================================================"
echo "USER PASSWORD STATUS"
echo "============================================================"
passwd -S "${USERNAME}"

echo
echo "============================================================"
echo "ROOT PASSWORD STATUS"
echo "============================================================"
passwd -S root

echo
echo "============================================================"
echo "KERNEL"
echo "============================================================"
pacman -Q linux

echo
echo "============================================================"
echo "XLIBRE"
echo "============================================================"
pacman -Q xlibre-meta

echo
echo "============================================================"
echo "DWM"
echo "============================================================"
pacman -Q dwm

echo
echo "============================================================"
echo "LIGHTDM"
echo "============================================================"
pacman -Q lightdm

echo
echo "============================================================"
echo "CONNMAN"
echo "============================================================"
pacman -Q connman

echo
echo "============================================================"
echo "INSTALLATION CHECKS COMPLETE"
echo "============================================================"
echo
echo "Username:   ${USERNAME}"
echo "Hostname:   ${HOSTNAME}"
echo "Desktop:    dwm"
echo "Display:    XLibre"
echo "Init:       OpenRC"
echo "Filesystem: XFS"
echo
echo "Root account: LOCKED"
echo
echo "Use:"
echo
echo "    sudo <command>"
echo
echo "for administrative tasks."
echo
echo "Steam, OBS Studio, and Kdenlive were NOT installed."
echo
echo "============================================================"

###############################################################################
# Cleanup
###############################################################################

rm -f /root/xlibre-artixlinux.asc
rm -f /root/install-vars
rm -f /root/install-chroot.sh

CHROOT

###############################################################################
# Make chroot script executable
###############################################################################

chmod 700 "$MNT/root/install-chroot.sh"

###############################################################################
# Run target installation
###############################################################################

log "Entering installed system..."

artix-chroot "$MNT" /root/install-chroot.sh

###############################################################################
# Remove any leftover sensitive files
###############################################################################

rm -f "$MNT/root/user-password"
rm -f "$MNT/root/install-vars"
rm -f "$MNT/root/install-chroot.sh"

###############################################################################
# Unmount
###############################################################################

log "Syncing filesystem..."

sync

log "Unmounting filesystems..."

umount -R "$MNT"

###############################################################################
# Final message
###############################################################################

echo
echo "============================================================"
echo "ARTIX LINUX INSTALLATION COMPLETED"
echo "============================================================"
echo
echo "Disk:       $TARGET_DISK"
echo "Hostname:   $HOSTNAME"
echo "Username:   $USERNAME"
echo "Timezone:   $TIMEZONE"
echo
echo "Desktop:    dwm"
echo "Display:    XLibre"
echo "Init:       OpenRC"
echo "Filesystem: XFS"
echo
echo "Root account: LOCKED"
echo
echo "Administration:"
echo "    sudo <command>"
echo
echo "NOT installed:"
echo "    Steam"
echo "    OBS Studio"
echo "    Kdenlive"
echo
echo "============================================================"
echo

read -r -p "Reboot now? [Y/n]: " REBOOT_CONFIRM

if [[ -z "$REBOOT_CONFIRM" || "$REBOOT_CONFIRM" =~ ^[Yy]$ ]]; then
    echo
    echo "Rebooting..."
    reboot
else
    echo
    echo "Installation finished. You can reboot manually."
fi
