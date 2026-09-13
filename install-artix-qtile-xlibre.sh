#!/usr/bin/env bash
#
# Artix Linux + XLibre + Qtile installer
# UEFI / OpenRC / XFS / LightDM / PipeWire / ConnMan / Flatpak
#
# Default target: /dev/nvme0n1
# Default user:   mike
#
# WARNING: This script ERASES THE SELECTED DISK.
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
    echo "ERROR: $*" >&2
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

if [[ "$EUID" -ne 0 ]]; then
    fail "Run this installer as root."
fi

[[ -b "$TARGET_DISK" ]] || \
    fail "Target disk $TARGET_DISK does not exist."

if [[ ! -d /sys/firmware/efi ]]; then
    fail "System is not booted in UEFI mode."
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
# Disk confirmation
###############################################################################

echo
echo "============================================================"
echo "WARNING: THE FOLLOWING DISK WILL BE COMPLETELY ERASED:"
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
echo "============================================================"
echo

read -r -p "Type ERASE to continue: " CONFIRM

[[ "$CONFIRM" == "ERASE" ]] || \
    fail "Installation cancelled."

###############################################################################
# Install live-environment prerequisites
###############################################################################

log "Installing live-environment disk tools..."

pacman -Sy --needed --noconfirm \
    gptfdisk \
    parted

command -v sgdisk >/dev/null 2>&1 || \
    fail "sgdisk is unavailable."

command -v partprobe >/dev/null 2>&1 || \
    fail "partprobe is unavailable."

###############################################################################
# Unmount existing target mounts
###############################################################################

log "Unmounting existing target mounts..."

umount -R "$MNT" 2>/dev/null || true
swapoff -a 2>/dev/null || true

###############################################################################
# Partition disk
###############################################################################

log "Wiping partition table and creating GPT..."

wipefs -af "$TARGET_DISK"

sgdisk --zap-all "$TARGET_DISK"
sgdisk --clear "$TARGET_DISK"

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

log "Creating filesystems..."

mkfs.fat -F32 "$EFI_PART"
mkfs.xfs -f "$ROOT_PART"

###############################################################################
# Mount filesystems
###############################################################################

log "Mounting filesystems..."

mount "$ROOT_PART" "$MNT"

mkdir -p "$MNT/boot/efi"

mount "$EFI_PART" "$MNT/boot/efi"

###############################################################################
# Install base Artix system
###############################################################################

log "Installing base Artix system..."

basestap \
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

fstabgen -U "$MNT" >> "$MNT/etc/fstab"

###############################################################################
# Create chroot installation script
#
# IMPORTANT:
# This is written to disk and executed normally instead of being piped
# through artix-chroot. That allows passwd to interact with the terminal.
###############################################################################

log "Preparing target-system configuration..."

cat > "$MNT/root/install-chroot.sh" <<'CHROOT'
#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Variables
###############################################################################

HOSTNAME="__HOSTNAME__"
USERNAME="__USERNAME__"
TIMEZONE="__TIMEZONE__"
KEYMAP="__KEYMAP__"
LOCALE="__LOCALE__"

###############################################################################
# Helpers
###############################################################################

log() {
    echo
    echo "==> $*"
}

fail() {
    echo
    echo "CHROOT ERROR: $*" >&2
    exit 1
}

###############################################################################
# Timezone
###############################################################################

log "Configuring timezone..."

ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime

hwclock --systohc

###############################################################################
# Locale
###############################################################################

log "Configuring locale..."

if ! grep -q "^${LOCALE} UTF-8" /etc/locale.gen; then
    echo "${LOCALE} UTF-8" >> /etc/locale.gen
else
    sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen
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

curl -O https://xlibre-artix.github.io/xlibre-artixlinux.asc

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

#
# Only Arch extra is enabled here.
#
# community and multilib are intentionally NOT enabled.
#

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
# Preflight package check
###############################################################################

log "Checking required packages..."

REQUIRED_PACKAGES=(
    xlibre-meta
    xlibre-video-amdgpu
    qtile
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
# Full system update
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
# Qtile / LightDM / desktop utilities
###############################################################################

log "Installing Qtile and desktop components..."

pacman -S --needed --noconfirm \
    qtile \
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

if ! id "${USERNAME}" >/dev/null 2>&1; then

    useradd \
        -m \
        -G wheel,audio,video \
        -s /bin/bash \
        "${USERNAME}"

fi

###############################################################################
# USER PASSWORD
#
# This is intentionally interactive.
#
# Because this script is executed directly through artix-chroot rather than
# receiving stdin from a heredoc, passwd can properly read from the terminal.
###############################################################################

echo
echo "============================================================"
echo "SET PASSWORD FOR USER: ${USERNAME}"
echo
echo "This is the password you will use with sudo."
echo "There is NO separate root password."
echo "============================================================"
echo

passwd "${USERNAME}"

###############################################################################
# Sudo
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
# Qtile XSession
###############################################################################

log "Creating Qtile desktop session..."

mkdir -p /usr/share/xsessions

cat > /usr/share/xsessions/qtile.desktop <<'EOF'
[Desktop Entry]
Name=Qtile
Comment=Qtile Window Manager
Exec=qtile start
Type=Application
DesktopNames=Qtile
EOF

###############################################################################
# LightDM
###############################################################################

log "Configuring LightDM..."

cat > /etc/lightdm/lightdm.conf <<'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=qtile
EOF

###############################################################################
# Starter Qtile configuration
###############################################################################

log "Creating starter Qtile configuration..."

USER_HOME="/home/${USERNAME}"

mkdir -p "${USER_HOME}/.config/qtile"

cat > "${USER_HOME}/.config/qtile/config.py" <<'EOF'
from libqtile import bar, layout, widget
from libqtile.config import Key, Screen
from libqtile.lazy import lazy
from libqtile.utils import guess_terminal

mod = "mod4"
terminal = guess_terminal()

keys = [
    Key([mod], "Return", lazy.spawn(terminal)),
    Key([mod], "r", lazy.spawn("rofi -show drun")),
    Key([mod], "q", lazy.window.kill()),
    Key([mod, "shift"], "r", lazy.reload_config()),
    Key([mod, "shift"], "q", lazy.shutdown()),
]

layouts = [
    layout.Monadtall(),
    layout.Max(),
]

widget_defaults = dict(
    font="JetBrains Mono",
    fontsize=14,
    padding=3,
)

screens = [
    Screen(
        top=bar.Bar(
            [
                widget.GroupBox(),
                widget.WindowName(),
                widget.Clock(format="%Y-%m-%d %H:%M"),
            ],
            24,
        )
    )
]

dgroups_key_binder = None
dgroups_app_rules = []

follow_mouse_focus = True
bring_front_click = False
cursor_warp = False
floating_layout = layout.Floating()
auto_fullscreen = True
focus_on_window_activation = "smart"

wmname = "LG3D"
EOF

chown -R "${USERNAME}:${USERNAME}" \
    "${USER_HOME}/.config"

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
# Final checks
###############################################################################

log "Running final checks..."

echo
echo "User:"
id "${USERNAME}"

echo
echo "User password status:"
passwd -S "${USERNAME}"

echo
echo "Root password status:"
passwd -S root

echo
echo "Kernel:"
pacman -Q linux

echo
echo "XLibre:"
pacman -Q xlibre-meta

echo
echo "Qtile:"
pacman -Q qtile

echo
echo "LightDM:"
pacman -Q lightdm

echo
echo "ConnMan:"
pacman -Q connman

echo
echo "============================================================"
echo "TARGET SYSTEM CONFIGURATION COMPLETE"
echo "============================================================"
echo
echo "Username:   ${USERNAME}"
echo "Hostname:   ${HOSTNAME}"
echo "Desktop:    Qtile"
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
rm -f /root/install-chroot.sh

CHROOT

###############################################################################
# Substitute configuration values into chroot script
###############################################################################

sed -i \
    -e "s|__HOSTNAME__|$(printf '%s' "$HOSTNAME" | sed 's/[&/\]/\\&/g')|g" \
    -e "s|__USERNAME__|$(printf '%s' "$USERNAME" | sed 's/[&/\]/\\&/g')|g" \
    -e "s|__TIMEZONE__|$(printf '%s' "$TIMEZONE" | sed 's/[&/\]/\\&/g')|g" \
    -e "s|__KEYMAP__|$(printf '%s' "$KEYMAP" | sed 's/[&/\]/\\&/g')|g" \
    -e "s|__LOCALE__|$(printf '%s' "$LOCALE" | sed 's/[&/\]/\\&/g')|g" \
    "$MNT/root/install-chroot.sh"

chmod +x "$MNT/root/install-chroot.sh"

###############################################################################
# Run chroot script
#
# IMPORTANT:
# Do NOT use:
#
# artix-chroot "$MNT" /bin/bash <<EOF
#
# here.
#
# The script is executed directly so passwd gets the real terminal.
###############################################################################

log "Entering installed system..."

artix-chroot "$MNT" /root/install-chroot.sh

###############################################################################
# Remove chroot script
###############################################################################

rm -f "$MNT/root/install-chroot.sh"

###############################################################################
# Unmount
###############################################################################

log "Unmounting filesystems..."

sync

umount -R "$MNT"

###############################################################################
# Finished
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
echo "Desktop:    Qtile"
echo "Display:    XLibre"
echo "Init:       OpenRC"
echo "Filesystem: XFS"
echo
echo "Root account is LOCKED."
echo "Use '$USERNAME' + sudo for administration."
echo
echo "Steam, OBS Studio, and Kdenlive were intentionally NOT installed."
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
fi#!/usr/bin/env bash
#
# Artix Linux + XLibre + Qtile installer
# UEFI / OpenRC / XFS / LightDM / PipeWire / ConnMan / Flatpak
#
# Default target: /dev/nvme0n1
# Default user:   mike
#
# WARNING: This script ERASES the selected disk.
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

warn() {
    echo
    echo "WARNING: $*" >&2
}

fail() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}

cleanup_on_error() {
    echo
    echo "Installation failed."
    echo "The system may be partially installed under $MNT."
}

trap cleanup_on_error ERR

require_root() {
    [[ "$EUID" -eq 0 ]] || fail "Run this installer as root."
}

###############################################################################
# Initial checks
###############################################################################

require_root

[[ -b "$TARGET_DISK" ]] || fail "Target disk $TARGET_DISK does not exist."

if [[ ! -d /sys/firmware/efi ]]; then
    fail "System is not booted in UEFI mode. Reboot the live ISO in UEFI mode."
fi

log "Checking network connectivity..."

if ! ping -c 1 -W 3 artixlinux.org >/dev/null 2>&1; then
    fail "Network connectivity check failed."
fi

###############################################################################
# User configuration
###############################################################################

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
# Disk confirmation
###############################################################################

echo
echo "============================================================"
echo "WARNING: THE FOLLOWING DISK WILL BE COMPLETELY ERASED:"
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
echo "============================================================"
echo

read -r -p "Type ERASE to continue: " CONFIRM

[[ "$CONFIRM" == "ERASE" ]] || fail "Installation cancelled."

###############################################################################
# Install live-environment prerequisites
###############################################################################

log "Installing live-environment disk tools..."

pacman -Sy --needed --noconfirm gptfdisk parted

command -v sgdisk >/dev/null 2>&1 || fail "sgdisk is unavailable."
command -v partprobe >/dev/null 2>&1 || fail "partprobe is unavailable."

###############################################################################
# Unmount anything currently mounted
###############################################################################

log "Unmounting existing target mounts..."

umount -R "$MNT" 2>/dev/null || true
swapoff -a 2>/dev/null || true

###############################################################################
# Partition disk
###############################################################################

log "Wiping partition table and creating GPT..."

wipefs -af "$TARGET_DISK"
sgdisk --zap-all "$TARGET_DISK"
sgdisk -o "$TARGET_DISK"

sgdisk \
    -n 1:1MiB:+512MiB \
    -t 1:ef00 \
    "$TARGET_DISK"

sgdisk \
    -n 2:0:0 \
    -t 2:8300 \
    "$TARGET_DISK"

partprobe "$TARGET_DISK"
sleep 2

[[ -b "$EFI_PART" ]] || fail "EFI partition $EFI_PART was not created."
[[ -b "$ROOT_PART" ]] || fail "Root partition $ROOT_PART was not created."

###############################################################################
# Filesystems
###############################################################################

log "Creating filesystems..."

mkfs.fat -F32 "$EFI_PART"
mkfs.xfs -f "$ROOT_PART"

###############################################################################
# Mount filesystems
###############################################################################

log "Mounting filesystems..."

mount "$ROOT_PART" "$MNT"

mkdir -p "$MNT/boot/efi"
mount "$EFI_PART" "$MNT/boot/efi"

###############################################################################
# Basestap
###############################################################################

log "Installing base Artix system..."

basestap_packages=(
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
)

basestrap "$MNT" "${basestap_packages[@]}"

###############################################################################
# Generate fstab
###############################################################################

log "Generating fstab..."

fstabgen -U "$MNT" >> "$MNT/etc/fstab"

###############################################################################
# Chroot variables
###############################################################################

cat > "$MNT/root/install-vars" <<EOF
HOSTNAME='$HOSTNAME'
USERNAME='$USERNAME'
TIMEZONE='$TIMEZONE'
KEYMAP='$KEYMAP'
LOCALE='$LOCALE'
EOF

###############################################################################
# Chroot installation
###############################################################################

log "Entering installed system..."

artix-chroot "$MNT" /bin/bash <<'CHROOT'
set -Eeuo pipefail

source /root/install-vars

export HOME=/root

###############################################################################
# Helpers
###############################################################################

fail() {
    echo
    echo "CHROOT ERROR: $*" >&2
    exit 1
}

log() {
    echo
    echo "==> $*"
}

###############################################################################
# Basic system configuration
###############################################################################

log "Configuring timezone..."

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

###############################################################################
# Locale
###############################################################################

log "Configuring locale..."

sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen

if ! grep -q "^${LOCALE} UTF-8" /etc/locale.gen; then
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

echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

###############################################################################
# Artix XLibre repository
###############################################################################

log "Configuring Artix XLibre repository..."

cd /root

curl -O https://xlibre-artix.github.io/xlibre-artixlinux.asc

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

pacman -Sy --needed --noconfirm artix-archlinux-support

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
# Preflight package check
###############################################################################

log "Checking required packages..."

REQUIRED_PACKAGES=(
    xlibre-meta
    xlibre-video-amdgpu
    qtile
    lightdm
    lightdm-gtk-greeter
    lightdm-openrc
    connman
    connman-openrc
)

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! pacman -Si "$pkg" >/dev/null 2>&1; then
        fail "Required package '$pkg' is unavailable."
    fi
done

###############################################################################
# Full system upgrade
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
# Qtile / LightDM / desktop utilities
###############################################################################

log "Installing Qtile and desktop components..."

pacman -S --needed --noconfirm \
    qtile \
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

log "Creating user '$USERNAME'..."

if ! id "$USERNAME" >/dev/null 2>&1; then
    useradd \
        -m \
        -G wheel,audio,video \
        -s /bin/bash \
        "$USERNAME"
fi

echo
echo "Set the password for user '$USERNAME'."
echo "This is the password you will use with sudo."
echo

passwd "$USERNAME"

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
# Root account
###############################################################################

log "Locking root account..."

passwd -l root

###############################################################################
# Qtile XSession
###############################################################################

log "Creating Qtile desktop session..."

mkdir -p /usr/share/xsessions

cat > /usr/share/xsessions/qtile.desktop <<'EOF'
[Desktop Entry]
Name=Qtile
Comment=Qtile Window Manager
Exec=qtile start
Type=Application
DesktopNames=Qtile
EOF

###############################################################################
# LightDM
###############################################################################

log "Configuring LightDM..."

cat > /etc/lightdm/lightdm.conf <<'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=qtile
EOF

###############################################################################
# Starter Qtile configuration
###############################################################################

log "Creating starter Qtile configuration..."

USER_HOME="/home/$USERNAME"

mkdir -p "$USER_HOME/.config/qtile"

cat > "$USER_HOME/.config/qtile/config.py" <<'EOF'
from libqtile import bar, layout, widget
from libqtile.config import Key, Screen
from libqtile.lazy import lazy
from libqtile.utils import guess_terminal

mod = "mod4"
terminal = guess_terminal()

keys = [
    Key([mod], "Return", lazy.spawn(terminal)),
    Key([mod], "r", lazy.spawn("rofi -show drun")),
    Key([mod], "q", lazy.window.kill()),
    Key([mod, "shift"], "r", lazy.reload_config()),
    Key([mod, "shift"], "q", lazy.shutdown()),
]

layouts = [
    layout.Monadtall(),
    layout.Max(),
]

widget_defaults = dict(
    font="JetBrains Mono",
    fontsize=14,
    padding=3,
)

screens = [
    Screen(
        top=bar.Bar(
            [
                widget.GroupBox(),
                widget.WindowName(),
                widget.Clock(format="%Y-%m-%d %H:%M"),
            ],
            24,
        )
    )
]

dgroups_key_binder = None
dgroups_app_rules = []

follow_mouse_focus = True
bring_front_click = False
cursor_warp = False
floating_layout = layout.Floating()
auto_fullscreen = True
focus_on_window_activation = "smart"

wmname = "LG3D"
EOF

chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config"

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

grub-mkconfig -o /boot/grub/grub.cfg

###############################################################################
# Initramfs
###############################################################################

log "Generating initramfs..."

mkinitcpio -P

###############################################################################
# XLibre verification helper
###############################################################################

log "Creating XLibre verification helper..."

cat > /usr/local/bin/check-xlibre <<'EOF'
#!/usr/bin/env bash

echo "Display server information:"
echo

if command -v xdpyinfo >/dev/null 2>&1; then
    xdpyinfo | grep -E "vendor string|vendor release|X.Org"
else
    echo "xdpyinfo is not installed."
fi

echo
echo "Installed XLibre packages:"
pacman -Q | grep -i xlibre || true

echo
echo "Video driver:"
pacman -Q xlibre-video-amdgpu 2>/dev/null || true
EOF

chmod +x /usr/local/bin/check-xlibre

###############################################################################
# Cleanup
###############################################################################

rm -f /root/xlibre-artixlinux.asc
rm -f /root/install-vars

###############################################################################
# Final checks
###############################################################################

log "Running final checks..."

id "$USERNAME"

passwd -S root
passwd -S "$USERNAME"

systemctl --version >/dev/null 2>&1 || true

echo
echo "Installed kernel:"
pacman -Q linux

echo
echo "XLibre:"
pacman -Q xlibre-meta

echo
echo "Qtile:"
pacman -Q qtile

echo
echo "LightDM:"
pacman -Q lightdm

echo
echo "Networking:"
pacman -Q connman

echo
echo "Root account status:"
passwd -S root

echo
echo "============================================================"
echo "Installation inside chroot completed successfully."
echo "============================================================"

CHROOT

###############################################################################
# Unmount
###############################################################################

log "Unmounting filesystems..."

sync

umount -R "$MNT"

###############################################################################
# Finished
###############################################################################

echo
echo "============================================================"
echo "Artix Linux installation completed."
echo "============================================================"
echo
echo "Disk:       $TARGET_DISK"
echo "Hostname:   $HOSTNAME"
echo "Username:   $USERNAME"
echo "Timezone:   $TIMEZONE"
echo
echo "Desktop:    Qtile"
echo "Display:    XLibre"
echo "Init:       OpenRC"
echo "Filesystem: XFS"
echo
echo "Root account is LOCKED."
echo "Use '$USERNAME' + sudo for administration."
echo
echo "Steam, OBS Studio, and Kdenlive were intentionally NOT installed."
echo "They can be installed after the first successful boot."
echo
echo "============================================================"
echo

read -r -p "Reboot now? [Y/n]: " REBOOT_CONFIRM

if [[ -z "$REBOOT_CONFIRM" || "$REBOOT_CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Rebooting..."
    reboot
else
    echo
    echo "Not rebooting."
    echo "You can reboot manually when ready."
fi
