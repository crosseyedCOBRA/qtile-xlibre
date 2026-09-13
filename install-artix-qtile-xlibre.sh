#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Artix Linux OpenRC + XLibre + Qtile Installer
#
# Target:
#   UEFI / GPT
#   /dev/nvme0n1
#   XFS
#   OpenRC
#   XLibre
#   Qtile
#   LightDM
#   AMD RX 7900 XT
#   Arch extra + multilib
#
# WARNING:
#   THIS SCRIPT WILL ERASE /dev/nvme0n1.
#
# Run from an Artix OpenRC live ISO as root.
# ============================================================

DISK="/dev/nvme0n1"
HOSTNAME="artix"
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"
USERNAME="mike"

MNT="/mnt"

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RESET='\033[0m'

info() {
    echo -e "${BLUE}==>${RESET} $*"
}

success() {
    echo -e "${GREEN}==>${RESET} $*"
}

warning() {
    echo -e "${YELLOW}WARNING:${RESET} $*"
}

error() {
    echo -e "${RED}ERROR:${RESET} $*" >&2
}

die() {
    error "$*"
    exit 1
}

# ------------------------------------------------------------
# Error handler
# ------------------------------------------------------------

trap 'error "Installation failed at line $LINENO."; error "The installed system may be incomplete."' ERR

# ------------------------------------------------------------
# Must be root
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    die "Run this script as root."
fi

# ------------------------------------------------------------
# Verify we're booted in UEFI mode
# ------------------------------------------------------------

if [[ ! -d /sys/firmware/efi ]]; then
    die "System is not booted in UEFI mode."
fi

# ------------------------------------------------------------
# Verify disk exists
# ------------------------------------------------------------

if [[ ! -b "$DISK" ]]; then
    die "$DISK does not exist."
fi

# ------------------------------------------------------------
# Verify network
# ------------------------------------------------------------

info "Testing network connectivity..."

if ! ping -c 2 -W 3 artixlinux.org >/dev/null 2>&1; then
    die "No network connectivity. Connect to the network first."
fi

success "Network connectivity confirmed."

# ------------------------------------------------------------
# Final warning
# ------------------------------------------------------------

clear

echo
echo "============================================================"
echo "        ARTIX + OPENRC + XLIBRE + QTILE INSTALLER"
echo "============================================================"
echo
echo "THIS WILL COMPLETELY ERASE:"
echo
echo "    $DISK"
echo
echo "The following will be installed:"
echo
echo "    Artix Linux"
echo "    OpenRC"
echo "    XFS"
echo "    XLibre"
echo "    Qtile"
echo "    LightDM"
echo "    AMD graphics stack"
echo "    Steam / Proton support"
echo "    Arch extra"
echo "    Arch multilib"
echo "    PipeWire"
echo "    Bluetooth"
echo "    Flatpak"
echo
echo "Hostname:       $HOSTNAME"
echo "Username:       $USERNAME"
echo "Timezone:       $TIMEZONE"
echo
echo "============================================================"
echo

read -rp "Type ERASE to continue: " CONFIRM

if [[ "$CONFIRM" != "ERASE" ]]; then
    die "Installation cancelled."
fi

# ------------------------------------------------------------
# Passwords
# ------------------------------------------------------------

echo
info "Set the password for root."
read -rsp "Root password: " ROOT_PASSWORD
echo
read -rsp "Confirm root password: " ROOT_PASSWORD_CONFIRM
echo

if [[ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]]; then
    die "Root passwords do not match."
fi

echo
info "Set the password for $USERNAME."
read -rsp "User password: " USER_PASSWORD
echo
read -rsp "Confirm user password: " USER_PASSWORD_CONFIRM
echo

if [[ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]]; then
    die "User passwords do not match."
fi

# ------------------------------------------------------------
# Prepare disk
# ------------------------------------------------------------

info "Unmounting anything currently mounted from $DISK..."

umount -R "$MNT" 2>/dev/null || true

info "Wiping old filesystem signatures..."

wipefs -af "$DISK"

info "Creating GPT partition table..."

parted -s "$DISK" mklabel gpt

info "Creating EFI partition..."

parted -s "$DISK" mkpart ESP fat32 1MiB 1025MiB
parted -s "$DISK" set 1 esp on

info "Creating XFS root partition..."

parted -s "$DISK" mkpart primary xfs 1025MiB 100%

# Give udev a moment to settle
sleep 2

EFI="${DISK}p1"
ROOT="${DISK}p2"

# ------------------------------------------------------------
# Format
# ------------------------------------------------------------

info "Formatting EFI partition..."

mkfs.fat -F32 "$EFI"

info "Formatting root partition as XFS..."

mkfs.xfs -f "$ROOT"

# ------------------------------------------------------------
# Mount
# ------------------------------------------------------------

info "Mounting root filesystem..."

mount "$ROOT" "$MNT"

mkdir -p "$MNT/boot/efi"

info "Mounting EFI partition..."

mount "$EFI" "$MNT/boot/efi"

# ------------------------------------------------------------
# Base installation
# ------------------------------------------------------------

info "Installing Artix base system..."

basestrap "$MNT" \
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

# ------------------------------------------------------------
# fstab
# ------------------------------------------------------------

info "Generating fstab..."

fstabgen -U "$MNT" >> "$MNT/etc/fstab"

# ------------------------------------------------------------
# Copy resolver configuration
# ------------------------------------------------------------

if [[ -f /etc/resolv.conf ]]; then
    cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"
fi

# ------------------------------------------------------------
# Copy script into installed system
# ------------------------------------------------------------

cp "$0" "$MNT/root/artix-qtile-xlibre-install.sh"

# ------------------------------------------------------------
# Create chroot configuration script
# ------------------------------------------------------------

cat > "$MNT/root/artix-configure.sh" <<'CHROOT_SCRIPT'
#!/usr/bin/env bash

set -Eeuo pipefail

DISK="/dev/nvme0n1"
EFI="${DISK}p1"
ROOT="${DISK}p2"

HOSTNAME="artix"
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"
USERNAME="mike"

ROOT_PASSWORD="__ROOT_PASSWORD__"
USER_PASSWORD="__USER_PASSWORD__"

info() {
    echo
    echo "==> $*"
}

# ------------------------------------------------------------
# Timezone
# ------------------------------------------------------------

info "Configuring timezone..."

ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

# ------------------------------------------------------------
# Locale
# ------------------------------------------------------------

info "Configuring locale..."

sed -i "s/^#${LOCALE} UTF-8$/${LOCALE} UTF-8/" /etc/locale.gen

# In case the line isn't commented in the expected format
grep -q "^${LOCALE} UTF-8" /etc/locale.gen || \
    echo "${LOCALE} UTF-8" >> /etc/locale.gen

locale-gen

echo "LANG=${LOCALE}" > /etc/locale.conf

# ------------------------------------------------------------
# Hostname
# ------------------------------------------------------------

info "Configuring hostname..."

echo "${HOSTNAME}" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# ------------------------------------------------------------
# Root password
# ------------------------------------------------------------

info "Setting root password..."

printf '%s\n' \
    "root:${ROOT_PASSWORD}" | chpasswd

# ------------------------------------------------------------
# Pacman configuration
# ------------------------------------------------------------

info "Configuring pacman..."

sed -i 's/^#Color$/Color/' /etc/pacman.conf
sed -i 's/^#ParallelDownloads = 5$/ParallelDownloads = 5/' /etc/pacman.conf

# ------------------------------------------------------------
# XLibre repository key
# ------------------------------------------------------------

info "Installing XLibre repository signing key..."

curl -fsSL \
    https://xlibre-artix.github.io/xlibre-artixlinux.asc \
    -o /root/xlibre-artixlinux.asc

pacman-key --add /root/xlibre-artixlinux.asc

pacman-key --finger 2AFFCD7B42ADD2E7

pacman-key --lsign-key 2AFFCD7B42ADD2E7

rm -f /root/xlibre-artixlinux.asc

# ------------------------------------------------------------
# Insert XLibre repository
#
# It MUST be after [system] and before [world].
# ------------------------------------------------------------

info "Configuring XLibre repository..."

python - <<'PY'
from pathlib import Path

p = Path("/etc/pacman.conf")
text = p.read_text()

repo = """\
[xlibre-stable]
Server = https://github.com/xlibre-artix/stable/releases/download/$arch

"""

if "[xlibre-stable]" not in text:
    marker = "[world]"
    if marker not in text:
        raise SystemExit("Could not find [world] in pacman.conf")

    text = text.replace(marker, repo + marker, 1)

p.write_text(text)
PY

# ------------------------------------------------------------
# Update Artix
# ------------------------------------------------------------

info "Synchronizing Artix repositories..."

pacman -Syyu --noconfirm

# ------------------------------------------------------------
# Arch Linux repository support
# ------------------------------------------------------------

info "Installing Artix Arch Linux repository support..."

pacman -S --noconfirm artix-archlinux-support

# ------------------------------------------------------------
# Add Arch extra + multilib
#
# DO NOT ADD ARCH CORE.
# ------------------------------------------------------------

info "Enabling Arch extra + multilib..."

python - <<'PY'
from pathlib import Path

p = Path("/etc/pacman.conf")
text = p.read_text()

arch_repos = """
# ============================================================
# Arch Linux repositories
#
# IMPORTANT:
# Do NOT enable [core].
# Artix [system] provides the core system layer.
# ============================================================

[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
"""

if "[extra]" not in text:
    text += "\n" + arch_repos + "\n"
elif "[multilib]" not in text:
    text += "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist-arch\n"

p.write_text(text)
PY

# ------------------------------------------------------------
# Populate Arch keys
# ------------------------------------------------------------

info "Populating Arch Linux package signing keys..."

pacman-key --populate archlinux

# ------------------------------------------------------------
# Update all repositories
# ------------------------------------------------------------

info "Performing full system update..."

pacman -Syyu --noconfirm

# ------------------------------------------------------------
# User
# ------------------------------------------------------------

info "Creating user ${USERNAME}..."

if ! id "${USERNAME}" >/dev/null 2>&1; then
    useradd \
        -m \
        -G wheel,audio,video,networkmanager \
        -s /bin/bash \
        "${USERNAME}"
fi

printf '%s\n' \
    "${USERNAME}:${USER_PASSWORD}" | chpasswd

# ------------------------------------------------------------
# Passwordless sudo
# ------------------------------------------------------------

info "Configuring passwordless sudo..."

cat > /etc/sudoers.d/wheel-nopasswd <<'EOF'
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
EOF

chmod 440 /etc/sudoers.d/wheel-nopasswd

visudo -c

# ------------------------------------------------------------
# OpenRC services
# ------------------------------------------------------------

info "Enabling OpenRC services..."

rc-update add NetworkManager default || true
rc-update add elogind boot || true

# ------------------------------------------------------------
# XLibre
# ------------------------------------------------------------

info "Installing XLibre..."

pacman -S --noconfirm xlibre-meta

# AMD driver
info "Installing AMD XLibre driver..."

pacman -S --noconfirm xlibre-video-amdgpu

# ------------------------------------------------------------
# X11 utilities
# ------------------------------------------------------------

info "Installing X11 utilities..."

pacman -S --noconfirm \
    xorg-xinit \
    xorg-xrandr \
    xorg-xset \
    xorg-xsetroot \
    xorg-xmodmap \
    xorg-xdpyinfo

# ------------------------------------------------------------
# AMD graphics / Vulkan / 32-bit
# ------------------------------------------------------------

info "Installing AMD graphics and Vulkan stack..."

pacman -S --noconfirm \
    mesa \
    lib32-mesa \
    vulkan-radeon \
    lib32-vulkan-radeon \
    vulkan-icd-loader \
    lib32-vulkan-icd-loader \
    libva-mesa-driver \
    mesa-vdpau \
    mesa-utils

# ------------------------------------------------------------
# Qtile
# ------------------------------------------------------------

info "Installing Qtile..."

pacman -S --noconfirm \
    qtile \
    python-psutil \
    alacritty

# ------------------------------------------------------------
# LightDM
# ------------------------------------------------------------

info "Installing LightDM..."

pacman -S --noconfirm \
    lightdm \
    lightdm-gtk-greeter \
    lightdm-openrc

rc-update add lightdm default

# ------------------------------------------------------------
# LightDM configuration
# ------------------------------------------------------------

mkdir -p /etc/lightdm

cat > /etc/lightdm/lightdm.conf <<'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
EOF

# ------------------------------------------------------------
# Qtile session
# ------------------------------------------------------------

info "Creating Qtile desktop session..."

mkdir -p /usr/share/xsessions

cat > /usr/share/xsessions/qtile.desktop <<'EOF'
[Desktop Entry]
Name=Qtile
Comment=Qtile Window Manager
Exec=qtile start
Type=Application
Keywords=wm;tiling
EOF

# ------------------------------------------------------------
# Desktop utilities
# ------------------------------------------------------------

info "Installing desktop utilities..."

pacman -S --noconfirm \
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

# ------------------------------------------------------------
# Fonts
# ------------------------------------------------------------

info "Installing fonts..."

pacman -S --noconfirm \
    ttf-jetbrains-mono-nerd \
    noto-fonts \
    noto-fonts-emoji

# ------------------------------------------------------------
# PipeWire
# ------------------------------------------------------------

info "Installing PipeWire..."

pacman -S --noconfirm \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    wireplumber \
    rtkit

# OpenRC integration if available
if pacman -Si pipewire-openrc >/dev/null 2>&1; then
    pacman -S --noconfirm pipewire-openrc
    rc-update add pipewire default || true
fi

# ------------------------------------------------------------
# Bluetooth
# ------------------------------------------------------------

info "Installing Bluetooth..."

pacman -S --noconfirm \
    bluez \
    bluez-utils \
    blueman

if pacman -Si bluez-openrc >/dev/null 2>&1; then
    pacman -S --noconfirm bluez-openrc
    rc-update add bluetooth default || true
fi

# ------------------------------------------------------------
# Flatpak
# ------------------------------------------------------------

info "Installing Flatpak..."

pacman -S --noconfirm flatpak

# ------------------------------------------------------------
# Steam
# ------------------------------------------------------------

info "Installing Steam..."

pacman -S --noconfirm steam

# ------------------------------------------------------------
# General utilities
# ------------------------------------------------------------

info "Installing general utilities..."

pacman -S --noconfirm \
    git \
    curl \
    wget \
    unzip \
    zip \
    tree \
    btop \
    htop \
    fastfetch \
    rsync \
    openssh

# ------------------------------------------------------------
# Development / ZarisWM tools
# ------------------------------------------------------------

info "Installing X11 development libraries..."

pacman -S --noconfirm \
    gcc \
    make \
    pkgconf \
    libx11 \
    libxft \
    libxinerama \
    libxrandr \
    libxext \
    libxrender \
    libxfixes \
    libxdamage \
    libxcomposite \
    libxcb

# ------------------------------------------------------------
# Firefox
# ------------------------------------------------------------

info "Installing Firefox..."

pacman -S --noconfirm firefox

# ------------------------------------------------------------
# Flatpak Flathub
# ------------------------------------------------------------

info "Adding Flathub..."

flatpak remote-add \
    --if-not-exists \
    flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

# ------------------------------------------------------------
# GRUB
# ------------------------------------------------------------

info "Installing GRUB..."

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=Artix \
    --recheck

grub-mkconfig -o /boot/grub/grub.cfg

# ------------------------------------------------------------
# Initramfs
# ------------------------------------------------------------

info "Rebuilding initramfs..."

mkinitcpio -P

# ------------------------------------------------------------
# Final package update
# ------------------------------------------------------------

info "Performing final system update..."

pacman -Syu --noconfirm

# ------------------------------------------------------------
# Verification
# ------------------------------------------------------------

info "Performing installation checks..."

echo
echo "============================================================"
echo "Repository check"
echo "============================================================"

pacman -Sl extra | head -n 5 || true
pacman -Sl multilib | head -n 5 || true

echo
echo "============================================================"
echo "XLibre"
echo "============================================================"

pacman -Q | grep xlibre || true

echo
echo "============================================================"
echo "Qtile"
echo "============================================================"

qtile --version || true

echo
echo "============================================================"
echo "LightDM"
echo "============================================================"

pacman -Q lightdm lightdm-gtk-greeter lightdm-openrc || true

echo
echo "============================================================"
echo "OpenRC services"
echo "============================================================"

rc-update show

echo
echo "============================================================"
echo "Installation complete"
echo "============================================================"
echo
echo "User:              ${USERNAME}"
echo "Hostname:          ${HOSTNAME}"
echo "Timezone:          ${TIMEZONE}"
echo "Desktop:           Qtile"
echo "Display manager:   LightDM"
echo "Display server:    XLibre"
echo "Init:              OpenRC"
echo
echo "Arch repositories:"
echo "    extra"
echo "    multilib"
echo
echo "Passwordless sudo: ENABLED"
echo
echo "============================================================"
echo
echo "After reboot:"
echo
echo "  1. Log into LightDM."
echo "  2. Select Qtile if necessary."
echo "  3. Log in."
echo "  4. Test:"
echo
echo "       echo \$XDG_SESSION_TYPE"
echo "       xdpyinfo | grep vendor"
echo "       glxinfo | grep 'OpenGL renderer'"
echo
echo "Expected:"
echo "       x11"
echo "       XLibre vendor information"
echo "       AMD Radeon RX 7900 XT / radeonsi"
echo
echo "============================================================"

CHROOT_SCRIPT

# Replace password placeholders safely
python - "$MNT/root/artix-configure.sh" "$ROOT_PASSWORD" "$USER_PASSWORD" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
root_password = sys.argv[2]
user_password = sys.argv[3]

text = path.read_text()

# Shell-safe single-quoted representation
def sq(s):
    return "'" + s.replace("'", "'\"'\"'") + "'"

text = text.replace(
    'ROOT_PASSWORD="__ROOT_PASSWORD__"',
    f'ROOT_PASSWORD={sq(root_password)}'
)

text = text.replace(
    'USER_PASSWORD="__USER_PASSWORD__"',
    f'USER_PASSWORD={sq(user_password)}'
)

path.write_text(text)
PY

chmod +x "$MNT/root/artix-configure.sh"

# ------------------------------------------------------------
# Chroot
# ------------------------------------------------------------

info "Entering installed system..."

artix-chroot "$MNT" /root/artix-configure.sh

# ------------------------------------------------------------
# Clean up
# ------------------------------------------------------------

rm -f "$MNT/root/artix-configure.sh"
rm -f "$MNT/root/artix-qtile-xlibre-install.sh"

# ------------------------------------------------------------
# Unmount
# ------------------------------------------------------------

info "Unmounting filesystems..."

sync

umount -R "$MNT"

success "Installation completed successfully."

echo
echo "You can now reboot."
echo
read -rp "Reboot now? [Y/n]: " REBOOT

if [[ ! "$REBOOT" =~ ^[Nn]$ ]]; then
    reboot
fi
