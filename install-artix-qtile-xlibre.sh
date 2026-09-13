#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Artix Linux OpenRC + XLibre + Qtile
#
# Target hardware:
#   Ryzen 7 7800X3D
#   Radeon RX 7900 XT
#
# Target configuration:
#   UEFI / GPT
#   XFS
#   OpenRC
#   XLibre
#   Qtile
#   LightDM
#   NetworkManager
#   PipeWire
#   Bluetooth
#   Flatpak
#   Steam
#   Arch extra
#   Arch multilib
#
# USER:
#   mike
#
# IMPORTANT:
#   - /dev/nvme0n1 WILL BE ERASED
#   - ROOT PASSWORD IS NOT SET
#   - ROOT ACCOUNT IS LOCKED
#   - mike gets passwordless sudo
# ============================================================

DISK="/dev/nvme0n1"
EFI="${DISK}p1"
ROOT="${DISK}p2"

MNT="/mnt"

USERNAME="mike"
HOSTNAME="artix"
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"

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

die() {
    echo -e "${RED}ERROR:${RESET} $*" >&2
    exit 1
}

trap 'die "Installation failed at line $LINENO."' ERR

# ============================================================
# PRE-FLIGHT
# ============================================================

if [[ $EUID -ne 0 ]]; then
    die "Run this script as root from the Artix live ISO."
fi

if [[ ! -d /sys/firmware/efi ]]; then
    die "The live ISO is not booted in UEFI mode."
fi

if [[ ! -b "$DISK" ]]; then
    die "$DISK does not exist."
fi

info "Checking network..."

if ! ping -c 2 -W 3 artixlinux.org >/dev/null 2>&1; then
    die "No network connectivity. Connect to the Internet before running this script."
fi

success "Network is working."

# ============================================================
# LIVE ISO DEPENDENCIES
# ============================================================

info "Installing live-ISO tools required by the installer..."

pacman -Sy --needed --noconfirm \
    parted \
    dosfstools \
    xfsprogs \
    gptfdisk \
    util-linux

# ============================================================
# WARNING
# ============================================================

clear

echo
echo "============================================================"
echo "       ARTIX OPENRC + XLIBRE + QTILE INSTALLER"
echo "============================================================"
echo
echo "THIS WILL COMPLETELY ERASE:"
echo
echo "    $DISK"
echo
echo "Installation:"
echo
echo "    Artix Linux"
echo "    OpenRC"
echo "    XFS"
echo "    XLibre"
echo "    Qtile"
echo "    LightDM"
echo "    AMD graphics"
echo "    Steam / Proton"
echo "    Arch extra"
echo "    Arch multilib"
echo "    PipeWire"
echo "    Bluetooth"
echo "    Flatpak"
echo
echo "User:"
echo
echo "    $USERNAME"
echo
echo "Root password:"
echo
echo "    NONE — root account will be locked"
echo
echo "Sudo:"
echo
echo "    PASSWORDLESS"
echo
echo "============================================================"
echo

read -rp "Type ERASE to continue: " CONFIRM

if [[ "$CONFIRM" != "ERASE" ]]; then
    die "Installation cancelled."
fi

# ============================================================
# USER PASSWORD
# ============================================================

echo
info "Set the password for $USERNAME."
echo "This is the only password you need."
echo

read -rsp "Password: " USER_PASSWORD
echo

read -rsp "Confirm password: " USER_PASSWORD_CONFIRM
echo

if [[ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]]; then
    die "Passwords do not match."
fi

# ============================================================
# UNMOUNT ANY EXISTING INSTALLATION
# ============================================================

info "Unmounting anything currently mounted under $MNT..."

umount -R "$MNT" 2>/dev/null || true

# ============================================================
# DISK
# ============================================================

info "Wiping existing filesystem signatures..."

wipefs -af "$DISK"

info "Creating GPT partition table..."

parted -s "$DISK" mklabel gpt

info "Creating EFI partition..."

parted -s "$DISK" \
    mkpart ESP fat32 1MiB 1025MiB

parted -s "$DISK" \
    set 1 esp on

info "Creating XFS root partition..."

parted -s "$DISK" \
    mkpart primary xfs 1025MiB 100%

# ------------------------------------------------------------
# IMPORTANT:
# Tell the kernel about the new partition table.
# This helps prevent fsconfig()/mount errors when the
# kernel has not yet noticed the newly created partitions.
# ------------------------------------------------------------

info "Refreshing kernel partition table..."

partprobe "$DISK" || true

udevadm settle

sleep 2

# ============================================================
# VERIFY PARTITIONS
# ============================================================

info "Verifying partitions..."

lsblk "$DISK"

if [[ ! -b "$EFI" ]]; then
    die "$EFI was not created."
fi

if [[ ! -b "$ROOT" ]]; then
    die "$ROOT was not created."
fi

success "Partitions detected:"
lsblk -o NAME,SIZE,TYPE,FSTYPE "$DISK"

# ============================================================
# FORMAT
# ============================================================

info "Formatting EFI partition..."

mkfs.fat -F32 "$EFI"

info "Formatting XFS root partition..."

mkfs.xfs -f "$ROOT"

udevadm settle

# ============================================================
# MOUNT
# ============================================================

info "Mounting root filesystem..."

mkdir -p "$MNT"

mount "$ROOT" "$MNT"

info "Mounting EFI filesystem..."

mkdir -p "$MNT/boot/efi"

mount "$EFI" "$MNT/boot/efi"

success "Filesystems mounted."

findmnt "$MNT"
findmnt "$MNT/boot/efi"

# ============================================================
# BASESTRAP
# ============================================================

info "Installing Artix base system..."

basestrap "$MNT" \
    base \
    base-devel \
    openrc \
    elogind-openrc \
    linux \
    linux-headers \
    linux-firmware \
    amd-ucode \
    xfsprogs \
    grub \
    efibootmgr \
    os-prober \
    nano \
    sudo \
    git \
    curl \
    wget \
    networkmanager \
    networkmanager-openrc

# ============================================================
# FSTAB
# ============================================================

info "Generating fstab..."

fstabgen -U "$MNT" > "$MNT/etc/fstab"

echo
cat "$MNT/etc/fstab"
echo

# ============================================================
# DNS
# ============================================================

if [[ -f /etc/resolv.conf ]]; then
    cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"
fi

# ============================================================
# CHROOT CONFIGURATION SCRIPT
# ============================================================

info "Preparing installed system configuration..."

cat > "$MNT/root/configure-artix.sh" <<'CHROOT'
#!/usr/bin/env bash

set -Eeuo pipefail

USERNAME="mike"
HOSTNAME="artix"
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"

USER_PASSWORD="__USER_PASSWORD__"

info() {
    echo
    echo "==> $*"
}

# ============================================================
# TIMEZONE
# ============================================================

info "Configuring timezone..."

ln -sf \
    "/usr/share/zoneinfo/${TIMEZONE}" \
    /etc/localtime

hwclock --systohc

# ============================================================
# LOCALE
# ============================================================

info "Configuring locale..."

sed -i \
    "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" \
    /etc/locale.gen

if ! grep -q "^${LOCALE} UTF-8" /etc/locale.gen; then
    echo "${LOCALE} UTF-8" >> /etc/locale.gen
fi

locale-gen

cat > /etc/locale.conf <<EOF
LANG=${LOCALE}
LC_COLLATE=C
EOF

# ============================================================
# HOSTNAME
# ============================================================

info "Configuring hostname..."

echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# ============================================================
# ROOT ACCOUNT
#
# NO ROOT PASSWORD.
# Lock root completely.
# ============================================================

info "Locking root account..."

passwd -l root

# ============================================================
# PACMAN
# ============================================================

info "Configuring pacman..."

sed -i 's/^#Color$/Color/' /etc/pacman.conf

sed -i \
    's/^#ParallelDownloads = 5/ParallelDownloads = 5/' \
    /etc/pacman.conf

# ============================================================
# XLIBRE KEY
# ============================================================

info "Installing XLibre signing key..."

curl -fsSL \
    https://xlibre-artix.github.io/xlibre-artixlinux.asc \
    -o /root/xlibre-artixlinux.asc

pacman-key --add /root/xlibre-artixlinux.asc

pacman-key --finger 2AFFCD7B42ADD2E7

pacman-key --lsign-key 2AFFCD7B42ADD2E7

rm -f /root/xlibre-artixlinux.asc

# ============================================================
# XLIBRE REPOSITORY
#
# Must be:
#
# [system]
# [xlibre-stable]
# [world]
# ============================================================

info "Adding XLibre repository..."

python - <<'PY'
from pathlib import Path

path = Path("/etc/pacman.conf")
text = path.read_text()

if "[xlibre-stable]" not in text:

    repo = """\
[xlibre-stable]
Server = https://github.com/xlibre-artix/stable/releases/download/$arch

"""

    marker = "[world]"

    if marker not in text:
        raise SystemExit(
            "Could not find [world] in /etc/pacman.conf"
        )

    text = text.replace(
        marker,
        repo + marker,
        1
    )

path.write_text(text)
PY

# ============================================================
# INITIAL SYSTEM UPDATE
# ============================================================

info "Updating Artix..."

pacman -Syyu --noconfirm

# ============================================================
# ARCH LINUX SUPPORT
# ============================================================

info "Installing Arch repository support..."

pacman -S --noconfirm \
    artix-archlinux-support

# ============================================================
# ARCH EXTRA + MULTILIB
#
# NO ARCH CORE.
# ============================================================

info "Enabling Arch extra and multilib..."

python - <<'PY'
from pathlib import Path

path = Path("/etc/pacman.conf")
text = path.read_text()

if "[extra]" not in text:

    text += """

# ============================================================
# Arch Linux repositories
#
# Arch core is intentionally NOT enabled.
# ============================================================

[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
"""

elif "[multilib]" not in text:

    text += """

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
"""

path.write_text(text)
PY

# ============================================================
# ARCH KEYRING
# ============================================================

info "Populating Arch Linux keys..."

pacman-key --populate archlinux

# ============================================================
# UPDATE WITH ARCH REPOS
# ============================================================

info "Updating with Arch extra/multilib enabled..."

pacman -Syyu --noconfirm

# ============================================================
# USER
# ============================================================

info "Creating user $USERNAME..."

if ! id "$USERNAME" >/dev/null 2>&1; then

    useradd \
        -m \
        -G wheel,audio,video,networkmanager \
        -s /bin/bash \
        "$USERNAME"

fi

printf '%s\n' \
    "${USERNAME}:${USER_PASSWORD}" | chpasswd

# ============================================================
# PASSWORDLESS SUDO
# ============================================================

info "Configuring passwordless sudo..."

cat > /etc/sudoers.d/wheel-nopasswd <<'EOF'
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
EOF

chmod 440 /etc/sudoers.d/wheel-nopasswd

visudo -c

# ============================================================
# OPENRC
# ============================================================

info "Configuring OpenRC services..."

rc-update add NetworkManager default || true

rc-update add elogind boot || true

# ============================================================
# XLIBRE
# ============================================================

info "Installing XLibre..."

pacman -S --noconfirm \
    xlibre-meta \
    xlibre-video-amdgpu

# ============================================================
# X11 UTILITIES
# ============================================================

info "Installing X11 utilities..."

pacman -S --noconfirm \
    xorg-xinit \
    xorg-xrandr \
    xorg-xset \
    xorg-xsetroot \
    xorg-xmodmap \
    xorg-xdpyinfo

# ============================================================
# AMD GRAPHICS
# ============================================================

info "Installing AMD graphics stack..."

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

# ============================================================
# QTILE
# ============================================================

info "Installing Qtile..."

pacman -S --noconfirm \
    qtile \
    python-psutil \
    alacritty

# ============================================================
# LIGHTDM
# ============================================================

info "Installing LightDM..."

pacman -S --noconfirm \
    lightdm \
    lightdm-gtk-greeter \
    lightdm-openrc

rc-update add lightdm default

mkdir -p /etc/lightdm

cat > /etc/lightdm/lightdm.conf <<'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
EOF

# ============================================================
# QTILE SESSION
# ============================================================

info "Creating Qtile session..."

mkdir -p /usr/share/xsessions

cat > /usr/share/xsessions/qtile.desktop <<'EOF'
[Desktop Entry]
Name=Qtile
Comment=Qtile Window Manager
Exec=qtile start
Type=Application
Keywords=wm;tiling
EOF

# ============================================================
# DESKTOP UTILITIES
# ============================================================

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

# ============================================================
# FONTS
# ============================================================

info "Installing fonts..."

pacman -S --noconfirm \
    ttf-jetbrains-mono-nerd \
    noto-fonts \
    noto-fonts-emoji

# ============================================================
# PIPEWIRE
# ============================================================

info "Installing PipeWire..."

pacman -S --noconfirm \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    wireplumber \
    rtkit

if pacman -Si pipewire-openrc >/dev/null 2>&1; then

    pacman -S --noconfirm \
        pipewire-openrc

    rc-update add pipewire default || true

fi

# ============================================================
# BLUETOOTH
# ============================================================

info "Installing Bluetooth..."

pacman -S --noconfirm \
    bluez \
    bluez-utils \
    blueman

if pacman -Si bluez-openrc >/dev/null 2>&1; then

    pacman -S --noconfirm \
        bluez-openrc

    rc-update add bluetooth default || true

fi

# ============================================================
# FLATPAK
# ============================================================

info "Installing Flatpak..."

pacman -S --noconfirm flatpak

# ============================================================
# STEAM
# ============================================================

info "Installing Steam..."

pacman -S --noconfirm steam

# ============================================================
# BASIC UTILITIES
# ============================================================

info "Installing basic utilities..."

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

# ============================================================
# ZARISWM / X11 DEVELOPMENT
# ============================================================

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

# ============================================================
# FIREFOX
# ============================================================

info "Installing Firefox..."

pacman -S --noconfirm firefox

# ============================================================
# FLATHUB
# ============================================================

info "Adding Flathub..."

flatpak remote-add \
    --if-not-exists \
    flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

# ============================================================
# GRUB
# ============================================================

info "Installing GRUB..."

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=Artix \
    --recheck

grub-mkconfig \
    -o /boot/grub/grub.cfg

# ============================================================
# INITRAMFS
# ============================================================

info "Rebuilding initramfs..."

mkinitcpio -P

# ============================================================
# FINAL UPDATE
# ============================================================

info "Performing final system update..."

pacman -Syu --noconfirm

# ============================================================
# VERIFY
# ============================================================

echo
echo "============================================================"
echo "                    INSTALLATION CHECK"
echo "============================================================"
echo

echo "--- Repositories ---"

pacman -Sl extra | head -n 5 || true
pacman -Sl multilib | head -n 5 || true

echo
echo "--- XLibre ---"

pacman -Q | grep xlibre || true

echo
echo "--- Qtile ---"

qtile --version || true

echo
echo "--- LightDM ---"

pacman -Q \
    lightdm \
    lightdm-gtk-greeter \
    lightdm-openrc || true

echo
echo "--- OpenRC ---"

rc-update show

echo
echo "============================================================"
echo "                  INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "User:              $USERNAME"
echo "Hostname:          $HOSTNAME"
echo "Desktop:           Qtile"
echo "Display Manager:   LightDM"
echo "Display Server:    XLibre"
echo "Init:              OpenRC"
echo
echo "Arch repositories:"
echo "    extra"
echo "    multilib"
echo
echo "Arch core:"
echo "    NOT ENABLED"
echo
echo "Root account:"
echo "    LOCKED"
echo
echo "Sudo:"
echo "    PASSWORDLESS"
echo
echo "============================================================"

CHROOT

# ============================================================
# INSERT USER PASSWORD SAFELY
# ============================================================

python - "$MNT/root/configure-artix.sh" "$USER_PASSWORD" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
password = sys.argv[2]

# Safely encode a shell single-quoted string.
safe = "'" + password.replace("'", "'\"'\"'") + "'"

text = path.read_text()

text = text.replace(
    'USER_PASSWORD="__USER_PASSWORD__"',
    f'USER_PASSWORD={safe}'
)

path.write_text(text)
PY

chmod 700 "$MNT/root/configure-artix.sh"

# ============================================================
# CHROOT
# ============================================================

info "Entering installed Artix system..."

artix-chroot "$MNT" /root/configure-artix.sh

# ============================================================
# REMOVE TEMPORARY CONFIGURATION
# ============================================================

rm -f "$MNT/root/configure-artix.sh"

# ============================================================
# FINAL SYNC
# ============================================================

sync

# ============================================================
# UNMOUNT
# ============================================================

info "Unmounting installed system..."

umount -R "$MNT"

success "Installation completed successfully."

echo
echo "============================================================"
echo
echo "Reboot when ready."
echo
echo "After reboot:"
echo
echo "  1. LightDM should appear."
echo "  2. Select Qtile."
echo "  3. Log in as mike."
echo
echo "Then test:"
echo
echo "    echo \$XDG_SESSION_TYPE"
echo "    xdpyinfo | grep vendor"
echo "    glxinfo | grep 'OpenGL renderer'"
echo
echo "Expected:"
echo
echo "    x11"
echo "    XLibre vendor information"
echo "    AMD Radeon / radeonsi"
echo
echo "============================================================"
