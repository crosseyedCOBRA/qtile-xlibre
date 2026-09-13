#!/bin/bash
set -euo pipefail

# Artix Linux OpenRC + XLibre + LightDM + Qtile + ConnMan
# UEFI / GPT / XFS / /dev/nvme0n1
#
# WARNING: THIS SCRIPT ERASES /dev/nvme0n1.

TARGET_DISK="/dev/nvme0n1"
EFI_PART="${TARGET_DISK}p1"
ROOT_PART="${TARGET_DISK}p2"
MNT="/mnt"

HOSTNAME_DEFAULT="artix"
USERNAME_DEFAULT="mike"
TIMEZONE_DEFAULT="America/New_York"
KEYMAP_DEFAULT="us"
LOCALE_DEFAULT="en_US.UTF-8"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# ------------------------------------------------------------
# Initial safety checks
# ------------------------------------------------------------

[[ $EUID -eq 0 ]] || fail "Run as root."

[[ -d /sys/firmware/efi ]] || \
    fail "Not booted in UEFI mode. Reboot the USB using its UEFI entry."

[[ -b "$TARGET_DISK" ]] || \
    fail "$TARGET_DISK not found."

ping -c1 -W3 artixlinux.org >/dev/null 2>&1 || \
    fail "No network connectivity."

clear || true

echo "============================================================"
echo " Artix OpenRC + XLibre + Qtile automated installer"
echo "============================================================"
echo
echo "Target:      $TARGET_DISK"
echo "Filesystem:  XFS"
echo "Boot:        UEFI / GPT"
echo "Init:        OpenRC"
echo "X server:    XLibre stable"
echo "WM:          Qtile"
echo "Display:     LightDM"
echo "Network:     ConnMan"
echo
echo "THIS WILL ERASE $TARGET_DISK"
echo

read -r -p 'Type ERASE to continue: ' confirm
[[ "$confirm" == "ERASE" ]] || fail "Cancelled."

read -r -p "Hostname [${HOSTNAME_DEFAULT}]: " HOSTNAME
HOSTNAME=${HOSTNAME:-$HOSTNAME_DEFAULT}

read -r -p "Username [${USERNAME_DEFAULT}]: " USERNAME
USERNAME=${USERNAME:-$USERNAME_DEFAULT}

read -r -p "Timezone [${TIMEZONE_DEFAULT}]: " TIMEZONE
TIMEZONE=${TIMEZONE:-$TIMEZONE_DEFAULT}

read -r -p "Keyboard [${KEYMAP_DEFAULT}]: " KEYMAP
KEYMAP=${KEYMAP:-$KEYMAP_DEFAULT}

# ------------------------------------------------------------
# Live environment prerequisites
# ------------------------------------------------------------

echo
echo "==> Installing live-environment partitioning tools..."

pacman -Sy --needed --noconfirm \
    gptfdisk \
    parted

command -v sgdisk >/dev/null 2>&1 || \
    fail "sgdisk is unavailable after installing gptfdisk."

command -v partprobe >/dev/null 2>&1 || \
    fail "partprobe is unavailable after installing parted."

# ------------------------------------------------------------
# Prepare disk
# ------------------------------------------------------------

echo
echo "==> Preparing disk..."

umount -R "$MNT" 2>/dev/null || true
swapoff -a 2>/dev/null || true

echo "==> Wiping partition information..."

wipefs -af "$TARGET_DISK"
sgdisk --zap-all "$TARGET_DISK"

echo "==> Creating GPT partition table..."

sgdisk -o "$TARGET_DISK"

echo "==> Creating EFI partition..."

sgdisk -n 1:1MiB:+512MiB \
       -t 1:ef00 \
       "$TARGET_DISK"

echo "==> Creating XFS root partition..."

sgdisk -n 2:0:0 \
       -t 2:8300 \
       "$TARGET_DISK"

partprobe "$TARGET_DISK"
sleep 2

# ------------------------------------------------------------
# Filesystems
# ------------------------------------------------------------

echo
echo "==> Creating filesystems..."

mkfs.fat -F32 "$EFI_PART"
mkfs.xfs -f "$ROOT_PART"

# ------------------------------------------------------------
# Mount filesystem
# ------------------------------------------------------------

echo
echo "==> Mounting filesystem..."

mount "$ROOT_PART" "$MNT"

mkdir -p "$MNT/boot/efi"

mount "$EFI_PART" "$MNT/boot/efi"

# ------------------------------------------------------------
# Base Artix installation
# ------------------------------------------------------------

echo
echo "==> Installing base Artix system..."

basestrap "$MNT" \
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

# ------------------------------------------------------------
# fstab
# ------------------------------------------------------------

echo
echo "==> Generating fstab..."

fstabgen -U "$MNT" > "$MNT/etc/fstab"

# ------------------------------------------------------------
# Installation variables
# ------------------------------------------------------------

cat > "$MNT/root/install-vars" <<EOFV
HOSTNAME=$(printf '%q' "$HOSTNAME")
USERNAME=$(printf '%q' "$USERNAME")
TIMEZONE=$(printf '%q' "$TIMEZONE")
KEYMAP=$(printf '%q' "$KEYMAP")
LOCALE=$(printf '%q' "$LOCALE_DEFAULT")
EOFV

# ------------------------------------------------------------
# Chroot configuration script
# ------------------------------------------------------------

cat > "$MNT/root/configure-artix.sh" <<'CHROOT'
#!/bin/bash
set -euo pipefail

source /root/install-vars

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# ============================================================
# Locale / time / hostname
# ============================================================

echo "==> Configuring locale, timezone and hostname..."

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime

hwclock --systohc

sed -i 's/^#\(en_US.UTF-8 UTF-8\)$/\1/' /etc/locale.gen

locale-gen

printf 'LANG=%s\n' "$LOCALE" > /etc/locale.conf

printf 'KEYMAP=%s\n' "$KEYMAP" > /etc/vconsole.conf

printf '%s\n' "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<EOFH
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOFH

# ============================================================
# Artix XLibre repository
# ============================================================

echo
echo "==> Configuring Artix XLibre repository..."

XLL_KEY=/root/xlibre-artixlinux.asc

curl -fsSL \
    https://xlibre-artix.github.io/xlibre-artixlinux.asc \
    -o "$XLL_KEY"

pacman-key --init

pacman-key --populate artix

pacman-key --add "$XLL_KEY"

pacman-key --finger 2AFFCD7B42ADD2E7

pacman-key --lsign-key 2AFFCD7B42ADD2E7

# XLibre must be after [system] and before [world].
if ! grep -q '^\[xlibre-stable\]' /etc/pacman.conf; then

    awk '
        /^\[world\]$/ && !added {
            print "[xlibre-stable]"
            print "Server = https://github.com/xlibre-artix/stable/releases/download/$arch"
            print ""
            added=1
        }
        {print}
    ' /etc/pacman.conf > /etc/pacman.conf.new

    mv /etc/pacman.conf.new /etc/pacman.conf
fi

# ============================================================
# Arch Linux repository support
# ============================================================

echo
echo "==> Enabling Arch Linux repository support..."

# artix-archlinux-support provides the Arch repository
# integration and Arch mirror list used by this installation.

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

# Only Arch extra is enabled.
# Community, multilib and Steam are intentionally omitted.
if ! grep -q '^\[extra\]' /etc/pacman.conf; then

    cat >> /etc/pacman.conf <<'EOFARCH'

# Arch Linux repository

[extra]
Include = /etc/pacman.d/mirrorlist-arch
EOFARCH

fi

[[ -s /etc/pacman.d/mirrorlist-arch ]] || \
    fail "Arch mirror list was not installed correctly."

echo
echo "==> Configured repositories:"

grep -E '^\[(system|xlibre-stable|world|galaxy|universe|extra)\]' \
    /etc/pacman.conf || true

# ============================================================
# Synchronize repositories
# ============================================================

echo
echo "==> Synchronizing package databases..."

pacman -Syy

echo
echo "==> Performing complete system upgrade..."

pacman -Su --noconfirm

# ============================================================
# Verify required packages
# ============================================================

echo
echo "==> Verifying required packages are available..."

REQUIRED_PACKAGES=(
    xlibre-meta
    xlibre-video-amdgpu
    qtile
    lightdm
    lightdm-gtk-greeter
    connman
    connman-openrc
)

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    echo "    Checking: $pkg"

    if ! pacman -Sp --print-format '%n' "$pkg" >/dev/null 2>&1; then
        fail "Required package is unavailable: $pkg"
    fi
done

echo
echo "==> Required package check passed."

# ============================================================
# XLibre
# ============================================================

echo
echo "==> Installing XLibre..."

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

# ============================================================
# Qtile + LightDM + X11 utilities
# ============================================================

echo
echo "==> Installing Qtile and X11 desktop..."

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

# ============================================================
# Audio
# ============================================================

echo
echo "==> Installing PipeWire..."

pacman -S --needed --noconfirm \
    pipewire \
    pipewire-audio \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    rtkit

# PipeWire is user-session based.
# Do NOT add a fake OpenRC system service.

# ============================================================
# Networking / Bluetooth
# ============================================================

echo
echo "==> Installing networking and Bluetooth..."

pacman -S --needed --noconfirm \
    connman \
    connman-openrc \
    bluez \
    bluez-utils \
    blueman

# ============================================================
# Flatpak / portals
# ============================================================

echo
echo "==> Installing Flatpak..."

pacman -S --needed --noconfirm \
    flatpak \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk

# ============================================================
# Utilities / fonts / development tools
# ============================================================

echo
echo "==> Installing utilities, fonts and development tools..."

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

# ============================================================
# User
# ============================================================

echo
echo "==> Creating user..."

if ! id "$USERNAME" >/dev/null 2>&1; then
    useradd \
        -m \
        -G wheel,audio,video \
        -s /bin/bash \
        "$USERNAME"
fi

echo
echo "Set root password:"
passwd root

echo
echo "Set password for $USERNAME:"
passwd "$USERNAME"

# ============================================================
# sudo
# ============================================================

echo
echo "==> Configuring sudo..."

if grep -q '^# %wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
    sed -i \
        's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' \
        /etc/sudoers
fi

# ============================================================
# Qtile LightDM session
# ============================================================

echo
echo "==> Configuring Qtile session..."

install -d /usr/share/xsessions

cat > /usr/share/xsessions/qtile.desktop <<'EOFSESSION'
[Desktop Entry]
Name=Qtile
Comment=Qtile Tiling Window Manager
Exec=qtile start
Type=Application
Keywords=wm;tiling
EOFSESSION

# ============================================================
# LightDM
# ============================================================

echo
echo "==> Configuring LightDM..."

cat > /etc/lightdm/lightdm.conf <<'EOFLIGHT'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=qtile
EOFLIGHT

# ============================================================
# Starter Qtile configuration
# ============================================================

echo
echo "==> Creating starter Qtile configuration..."

install -d \
    -o "$USERNAME" \
    -g "$USERNAME" \
    "/home/$USERNAME/.config/qtile"

cat > "/home/$USERNAME/.config/qtile/config.py" <<'EOFQTILE'
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
EOFQTILE

chown -R \
    "$USERNAME:$USERNAME" \
    "/home/$USERNAME/.config"

# ============================================================
# OpenRC services
# ============================================================

echo
echo "==> Configuring OpenRC services..."

rc-update add connmand default || true
rc-update add elogind boot || true
rc-update add dbus default || true
rc-update add lightdm default || true

if [[ -x /etc/init.d/bluetooth ]]; then
    rc-update add bluetooth default || true
fi

# ============================================================
# GRUB
# ============================================================

echo
echo "==> Installing GRUB..."

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=Artix \
    --recheck

grub-mkconfig -o /boot/grub/grub.cfg

# ============================================================
# Initramfs
# ============================================================

echo
echo "==> Generating initramfs..."

mkinitcpio -P

# ============================================================
# XLibre verification helper
# ============================================================

echo
echo "==> Installing XLibre verification helper..."

cat > /usr/local/bin/check-xlibre <<'EOFVERIFY'
#!/bin/sh

set -eu

if ! command -v xdpyinfo >/dev/null 2>&1; then
    echo "xdpyinfo is not installed."
    exit 1
fi

if ! xdpyinfo >/tmp/check-xlibre-output 2>&1; then
    echo
    echo "X server is not currently accessible."
    echo "Run this command after logging into the graphical session."
    rm -f /tmp/check-xlibre-output
    exit 1
fi

grep -Ei 'vendor|X\.Org|XLibre' /tmp/check-xlibre-output || true

rm -f /tmp/check-xlibre-output
EOFVERIFY

chmod +x /usr/local/bin/check-xlibre

# ============================================================
# Cleanup
# ============================================================

rm -f \
    /root/install-vars \
    /root/configure-artix.sh \
    /root/xlibre-artixlinux.asc

echo
echo "============================================================"
echo " Target system configuration complete."
echo "============================================================"
echo
echo "Installed:"
echo "  - Artix Linux / OpenRC"
echo "  - XLibre stable"
echo "  - AMD XLibre driver"
echo "  - LightDM"
echo "  - Qtile"
echo "  - PipeWire / WirePlumber"
echo "  - ConnMan"
echo "  - Bluetooth"
echo "  - Flatpak"
echo "  - X11 utilities"
echo
echo "After first login, run:"
echo
echo "    check-xlibre"
echo
echo "to verify the X server."
echo

CHROOT

chmod +x "$MNT/root/configure-artix.sh"

# ------------------------------------------------------------
# Run target configuration
# ------------------------------------------------------------

echo
echo "==> Entering installed system..."

artix-chroot "$MNT" /root/configure-artix.sh

# ------------------------------------------------------------
# Finish
# ------------------------------------------------------------

sync

echo
echo "==> Unmounting filesystems..."

umount -R "$MNT"

echo
echo "============================================================"
echo " Installation complete."
echo "============================================================"
echo
echo "Remove the USB and reboot."
echo

read -r -p "Reboot now? [Y/n]: " reboot_confirm

if [[ -z "$reboot_confirm" || "$reboot_confirm" =~ ^[Yy]$ ]]; then
    reboot
else
    echo
    echo "Not rebooting."
    echo "You can reboot manually when ready."
fi
