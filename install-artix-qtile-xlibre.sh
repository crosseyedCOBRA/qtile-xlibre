#!/usr/bin/env bash
#
# Artix Linux + OpenRC + XLibre + Qtile
# UEFI / GPT / XFS
#
# Target:
#   /dev/nvme0n1
#
# User:
#   mike
#
# Features:
#   - Artix OpenRC
#   - XLibre stable
#   - Qtile
#   - LightDM
#   - NetworkManager
#   - PipeWire
#   - Bluetooth
#   - AMD RX 7900 XT support
#   - Arch extra + multilib
#   - Steam
#   - Flatpak + Flathub
#   - passwordless sudo for wheel
#   - root account locked; no root password
#
# WARNING:
#   THIS WILL ERASE /dev/nvme0n1
#

set -Eeuo pipefail

#######################################
# Variables
#######################################

DISK="/dev/nvme0n1"
EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"

USERNAME="mike"
HOSTNAME="artix"
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"

MOUNTPOINT="/mnt"

#######################################
# Colors / helpers
#######################################

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

msg() {
    echo -e "${CYAN}==>${NC} $*"
}

success() {
    echo -e "${GREEN}==>${NC} $*"
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $*"
}

die() {
    echo -e "${RED}ERROR:${NC} $*" >&2
    exit 1
}

#######################################
# Root check
#######################################

if [[ "${EUID}" -ne 0 ]]; then
    die "Run this script as root."
fi

#######################################
# UEFI check
#######################################

if [[ ! -d /sys/firmware/efi ]]; then
    die "The live environment was not booted in UEFI mode."
fi

#######################################
# Disk check
#######################################

if [[ ! -b "$DISK" ]]; then
    die "$DISK does not exist."
fi

msg "Target disk:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$DISK"

echo
warn "THIS SCRIPT WILL COMPLETELY ERASE:"
echo "    $DISK"
echo
read -r -p "Type ERASE to continue: " CONFIRM

if [[ "$CONFIRM" != "ERASE" ]]; then
    die "Installation cancelled."
fi

#######################################
# Password
#######################################

echo
msg "Create the password for user '$USERNAME'."
echo "This will be the ONLY password requested."
echo
echo "The root account will be LOCKED."
echo "The '$USERNAME' account will have passwordless sudo."
echo

read -r -s -p "Password for $USERNAME: " USER_PASSWORD
echo
read -r -s -p "Confirm password: " USER_PASSWORD_CONFIRM
echo

if [[ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]]; then
    die "Passwords do not match."
fi

if [[ -z "$USER_PASSWORD" ]]; then
    die "Password cannot be empty."
fi

unset USER_PASSWORD_CONFIRM

#######################################
# Live ISO dependencies
#######################################

msg "Installing live-ISO tools..."

pacman -Syu --needed --noconfirm \
    parted \
    dosfstools \
    xfsprogs \
    gptfdisk \
    util-linux \
    curl \
    wget

#######################################
# Verify required Artix tools
#######################################

command -v basestrap >/dev/null 2>&1 \
    || die "basestrap is not available."

command -v fstabgen >/dev/null 2>&1 \
    || die "fstabgen is not available."

command -v artix-chroot >/dev/null 2>&1 \
    || die "artix-chroot is not available."

#######################################
# Unmount anything currently mounted
#######################################

msg "Unmounting anything currently mounted from target disk..."

umount -R "$MOUNTPOINT" 2>/dev/null || true

#######################################
# Wipe disk
#######################################

msg "Wiping partition table..."

wipefs -af "$DISK"
sgdisk --zap-all "$DISK"

#######################################
# Create GPT partition table
#######################################

msg "Creating GPT partition table..."

parted -s "$DISK" mklabel gpt

parted -s "$DISK" mkpart ESP fat32 1MiB 1025MiB
parted -s "$DISK" set 1 esp on

parted -s "$DISK" mkpart primary xfs 1025MiB 100%

#######################################
# Make kernel reread partition table
#######################################

msg "Refreshing partition table..."

partprobe "$DISK" || true
udevadm settle || true
sleep 3

#######################################
# Verify partitions
#######################################

msg "Checking for created partitions..."

if [[ ! -b "$EFI_PART" ]]; then
    lsblk "$DISK"
    die "$EFI_PART was not created."
fi

if [[ ! -b "$ROOT_PART" ]]; then
    lsblk "$DISK"
    die "$ROOT_PART was not created."
fi

success "Partitions detected."

lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$DISK"

#######################################
# Format
#######################################

msg "Formatting EFI partition..."

mkfs.fat -F32 "$EFI_PART"

msg "Formatting root partition as XFS..."

mkfs.xfs -f "$ROOT_PART"

#######################################
# Mount
#######################################

msg "Mounting root filesystem..."

mount "$ROOT_PART" "$MOUNTPOINT"

mkdir -p "$MOUNTPOINT/boot/efi"

msg "Mounting EFI filesystem..."

mount "$EFI_PART" "$MOUNTPOINT/boot/efi"

#######################################
# Verify mounts
#######################################

msg "Verifying mounts..."

findmnt "$MOUNTPOINT"
findmnt "$MOUNTPOINT/boot/efi"

#######################################
# Base installation
#######################################

msg "Installing Artix base system..."

basestrap "$MOUNTPOINT" \
    base \
    base-devel \
    linux \
    linux-headers \
    linux-firmware \
    openrc \
    elogind-openrc \
    xfsprogs \
    efibootmgr \
    grub \
    os-prober \
    nano \
    sudo \
    git \
    curl \
    wget \
    networkmanager \
    networkmanager-openrc

#######################################
# Generate fstab
#######################################

msg "Generating fstab..."

fstabgen -U "$MOUNTPOINT" >> "$MOUNTPOINT/etc/fstab"

#######################################
# Resolver
#######################################

if [[ -e /etc/resolv.conf ]]; then
    cp -L /etc/resolv.conf "$MOUNTPOINT/etc/resolv.conf"
fi

#######################################
# Prepare chroot configuration
#######################################

msg "Preparing chroot configuration..."

# Bash printf safely quotes the password for insertion into the chroot script.
# This replaces the previous Python dependency.
USER_PASSWORD_ESCAPED="$(printf '%q' "$USER_PASSWORD")"

unset USER_PASSWORD

cat > "$MOUNTPOINT/root/artix-configure.sh" <<EOF
#!/usr/bin/env bash

set -Eeuo pipefail

USERNAME="$USERNAME"
HOSTNAME="$HOSTNAME"
TIMEZONE="$TIMEZONE"
LOCALE="$LOCALE"

USER_PASSWORD=$USER_PASSWORD_ESCAPED

#######################################
# Basic system configuration
#######################################

echo "Configuring timezone..."

ln -sf "/usr/share/zoneinfo/\$TIMEZONE" /etc/localtime
hwclock --systohc

#######################################
# Locale
#######################################

echo "Configuring locale..."

sed -i "s/^#\${LOCALE}/\${LOCALE}/" /etc/locale.gen

locale-gen

cat > /etc/locale.conf <<LOCALEEOF
LANG=\${LOCALE}
LC_ADDRESS=\${LOCALE}
LC_IDENTIFICATION=\${LOCALE}
LC_MEASUREMENT=\${LOCALE}
LC_MONETARY=\${LOCALE}
LC_NAME=\${LOCALE}
LC_NUMERIC=\${LOCALE}
LC_PAPER=\${LOCALE}
LC_TELEPHONE=\${LOCALE}
LC_TIME=\${LOCALE}
LOCALEEOF

#######################################
# Hostname
#######################################

echo "Configuring hostname..."

echo "\$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<HOSTEOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \$HOSTNAME.localdomain \$HOSTNAME
HOSTEOF

#######################################
# Pacman configuration
#######################################

echo "Configuring pacman..."

sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf

#######################################
# XLibre repository
#######################################

echo "Installing XLibre signing key..."

curl -fsSL \
    https://xlibre-artix.github.io/xlibre-artixlinux.asc \
    -o /tmp/xlibre-artixlinux.asc

pacman-key --add /tmp/xlibre-artixlinux.asc

pacman-key --finger 2AFFCD7B42ADD2E7

pacman-key --lsign-key 2AFFCD7B42ADD2E7

rm -f /tmp/xlibre-artixlinux.asc

#######################################
# Add XLibre repository
#######################################

echo "Adding XLibre repository..."

if ! grep -q '^\\[xlibre-stable\\]' /etc/pacman.conf; then
    sed -i '/^\\[world\\]/i\\[xlibre-stable\\]\\nServer = https://github.com/xlibre-artix/stable/releases/download/\$arch\\n' /etc/pacman.conf
fi

#######################################
# Update Artix
#######################################

echo "Updating Artix package database..."

pacman -Syyu --noconfirm

#######################################
# Arch Linux repository support
#######################################

echo "Installing Arch Linux repository support..."

pacman -S --needed --noconfirm artix-archlinux-support

#######################################
# Arch repositories
#######################################

echo "Configuring Arch repositories..."

# Remove any existing Arch repo blocks so we do not duplicate them.
sed -i '/^\\[core\\]/,/^$/d' /etc/pacman.conf
sed -i '/^\\[extra\\]/,/^$/d' /etc/pacman.conf
sed -i '/^\\[multilib\\]/,/^$/d' /etc/pacman.conf
sed -i '/^\\[community\\]/,/^$/d' /etc/pacman.conf

cat >> /etc/pacman.conf <<'PACMANEOF

# Arch Linux repositories
# DO NOT enable Arch core on Artix.
# Artix [system] provides the core layer.

[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
PACMANEOF

#######################################
# Populate Arch keyring
#######################################

echo "Populating Arch Linux keys..."

pacman-key --populate archlinux

#######################################
# Update after Arch repository setup
#######################################

echo "Performing full system update..."

pacman -Syyu --noconfirm

#######################################
# User
#######################################

echo "Creating user \$USERNAME..."

if ! id "\$USERNAME" >/dev/null 2>&1; then
    useradd \
        -m \
        -G wheel,audio,video,networkmanager \
        -s /bin/bash \
        "\$USERNAME"
else
    usermod -aG wheel,audio,video,networkmanager "\$USERNAME"
fi

#######################################
# Set user password
#######################################

echo "Setting user password..."

printf '%s:%s\\n' "\$USERNAME" "\$USER_PASSWORD" | chpasswd

unset USER_PASSWORD

#######################################
# Lock root
#######################################

echo "Locking root account..."

passwd -l root

#######################################
# Passwordless sudo
#######################################

echo "Configuring passwordless sudo..."

mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/wheel-nopasswd <<SUDOEOF
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
SUDOEOF

chmod 0440 /etc/sudoers.d/wheel-nopasswd

visudo -c

#######################################
# Enable services
#######################################

echo "Enabling NetworkManager..."

rc-update add NetworkManager default

echo "Enabling elogind..."

rc-update add elogind boot

#######################################
# XLibre
#######################################

echo "Installing XLibre..."

pacman -S --needed --noconfirm \
    xlibre-meta \
    xlibre-video-amdgpu

#######################################
# X11 utilities
#######################################

echo "Installing X11 utilities..."

pacman -S --needed --noconfirm \
    xorg-xinit \
    xorg-xrandr \
    xorg-xsetroot \
    xorg-xdpyinfo \
    xorg-xset \
    xorg-xprop \
    xorg-xinput \
    xorg-xev \
    xorg-xmodmap \
    xorg-xwayland

#######################################
# AMD graphics
#######################################

echo "Installing AMD graphics stack..."

pacman -S --needed --noconfirm \
    mesa \
    lib32-mesa \
    vulkan-radeon \
    lib32-vulkan-radeon \
    vulkan-icd-loader \
    lib32-vulkan-icd-loader \
    libva-mesa-driver \
    mesa-vdpau \
    mesa-utils

#######################################
# Qtile
#######################################

echo "Installing Qtile..."

pacman -S --needed --noconfirm \
    qtile \
    python-psutil

#######################################
# Terminal
#######################################

echo "Installing Alacritty..."

pacman -S --needed --noconfirm \
    alacritty

#######################################
# LightDM
#######################################

echo "Installing LightDM..."

pacman -S --needed --noconfirm \
    lightdm \
    lightdm-gtk-greeter \
    lightdm-openrc

#######################################
# Qtile desktop entry
#######################################

echo "Creating Qtile session..."

mkdir -p /usr/share/xsessions

cat > /usr/share/xsessions/qtile.desktop <<QTILEEOF
[Desktop Entry]
Name=Qtile
Comment=Qtile Window Manager
Exec=qtile start
TryExec=qtile
Type=Application
DesktopNames=Qtile
QTILEEOF

#######################################
# Enable LightDM
#######################################

echo "Enabling LightDM..."

rc-update add lightdm default

#######################################
# Desktop utilities
#######################################

echo "Installing desktop utilities..."

pacman -S --needed --noconfirm \
    rofi \
    dunst \
    picom \
    feh \
    thunar \
    thunar-volman \
    tumbler \
    pavucontrol \
    flameshot \
    i3lock \
    wmctrl \
    xclip \
    xdotool \
    network-manager-applet \
    gvfs \
    gvfs-mtp \
    file-roller

#######################################
# Fonts
#######################################

echo "Installing fonts..."

pacman -S --needed --noconfirm \
    ttf-jetbrains-mono-nerd \
    noto-fonts \
    noto-fonts-emoji

#######################################
# PipeWire
#######################################

echo "Installing PipeWire..."

pacman -S --needed --noconfirm \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    wireplumber \
    rtkit

if pacman -Si pipewire-openrc >/dev/null 2>&1; then
    pacman -S --needed --noconfirm pipewire-openrc
    rc-update add pipewire default || true
fi

#######################################
# Bluetooth
#######################################

echo "Installing Bluetooth..."

pacman -S --needed --noconfirm \
    bluez \
    bluez-utils \
    blueman

if pacman -Si bluez-openrc >/dev/null 2>&1; then
    pacman -S --needed --noconfirm bluez-openrc
    rc-update add bluetooth default || true
fi

#######################################
# Flatpak
#######################################

echo "Installing Flatpak..."

pacman -S --needed --noconfirm \
    flatpak

#######################################
# Steam
#######################################

echo "Installing Steam..."

pacman -S --needed --noconfirm \
    steam

#######################################
# General utilities
#######################################

echo "Installing general utilities..."

pacman -S --needed --noconfirm \
    unzip \
    zip \
    p7zip \
    rsync \
    htop \
    btop \
    tree \
    man-db \
    man-pages \
    bash-completion \
    which \
    openssh \
    usbutils \
    pciutils

#######################################
# ZarisWM development dependencies
#######################################

echo "Installing ZarisWM development dependencies..."

pacman -S --needed --noconfirm \
    gcc \
    clang \
    make \
    cmake \
    meson \
    ninja \
    pkgconf \
    git \
    gdb \
    valgrind \
    libx11 \
    libxext \
    libxinerama \
    libxrandr \
    libxrender \
    libxfixes \
    libxcomposite \
    libxdamage \
    libxcb \
    xcb-util \
    xcb-util-wm \
    xcb-util-keysyms \
    xcb-util-image \
    xcb-util-renderutil \
    xcb-util-cursor \
    libxkbcommon \
    libxkbcommon-x11

#######################################
# Firefox
#######################################

echo "Installing Firefox..."

pacman -S --needed --noconfirm \
    firefox

#######################################
# Flathub
#######################################

echo "Adding Flathub..."

flatpak remote-add --if-not-exists \
    flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

#######################################
# GRUB
#######################################

echo "Installing GRUB..."

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=Artix \
    --recheck

#######################################
# GRUB configuration
#######################################

echo "Generating GRUB configuration..."

grub-mkconfig -o /boot/grub/grub.cfg

#######################################
# mkinitcpio
#######################################

echo "Regenerating initramfs..."

mkinitcpio -P

#######################################
# Final update
#######################################

echo "Performing final system update..."

pacman -Syu --noconfirm

#######################################
# Permissions
#######################################

chmod 700 /home/\$USERNAME
chown -R "\$USERNAME:\$USERNAME" /home/\$USERNAME

#######################################
# Verification
#######################################

echo
echo "=========================================="
echo " Installation verification"
echo "=========================================="
echo

echo "Kernel:"
uname -r

echo
echo "XLibre:"
if command -v xdpyinfo >/dev/null 2>&1; then
    xdpyinfo 2>/dev/null | grep -i vendor || true
fi

echo
echo "Qtile:"
qtile --version || true

echo
echo "NetworkManager:"
rc-status | grep -i NetworkManager || true

echo
echo "LightDM:"
rc-status | grep -i lightdm || true

echo
echo "User:"
id "\$USERNAME"

echo
echo "Sudo configuration:"
visudo -c

echo
echo "=========================================="
echo " Installation configuration complete"
echo "=========================================="
echo
echo "User:       \$USERNAME"
echo "Hostname:   \$HOSTNAME"
echo "Filesystem: XFS"
echo "Init:       OpenRC"
echo "Display:    XLibre"
echo "WM:         Qtile"
echo "Login:      LightDM"
echo
echo "Root account is LOCKED."
echo "User \$USERNAME has PASSWORDLESS sudo."
echo
EOF

chmod 700 "$MOUNTPOINT/root/artix-configure.sh"

#######################################
# Chroot
#######################################

msg "Entering installed system..."

artix-chroot "$MOUNTPOINT" /root/artix-configure.sh

#######################################
# Cleanup
#######################################

msg "Removing temporary configuration..."

rm -f "$MOUNTPOINT/root/artix-configure.sh"

#######################################
# Final filesystem sync
#######################################

sync

#######################################
# Show installed system
#######################################

echo
echo "=============================================="
echo "       ARTIX INSTALLATION COMPLETE"
echo "=============================================="
echo
echo "Drive:      $DISK"
echo "Filesystem: XFS"
echo "Init:       OpenRC"
echo "Display:    XLibre"
echo "WM:         Qtile"
echo "Login:      LightDM"
echo "User:       $USERNAME"
echo "Hostname:   $HOSTNAME"
echo
echo "Root account: LOCKED"
echo "Sudo:          PASSWORDLESS"
echo
echo "Unmounting filesystems..."
echo

umount -R "$MOUNTPOINT"

sync

echo
success "Installation complete."
echo
echo "Remove the installation media and reboot."
echo
read -r -p "Press ENTER to reboot, or Ctrl+C to remain in the live environment..."

reboot
