#!/bin/bash

set -euo pipefail

# ============================================================
# Artix Linux OpenRC + Btrfs + XLibre + Qtile Installer
#
# Target:
#   /dev/nvme0n1
#
# Filesystem:
#   Btrfs
#
# Init:
#   OpenRC
#
# Desktop:
#   XLibre + Qtile + LightDM GTK
#
# Hardware:
#   AMD RX 7900 XT
#
# Network:
#   Ethernet
#
# User:
#   mike
#
# WARNING:
#   THIS SCRIPT ERASES /dev/nvme0n1
# ============================================================

DISK="/dev/nvme0n1"
HOSTNAME="artix"
USERNAME="mike"
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"

MNT="/mnt"
CHROOT_SCRIPT="/root/artix-chroot-install.sh"

# ------------------------------------------------------------
# Colors / helpers
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() {
    echo -e "${CYAN}==> $1${NC}"
}

success() {
    echo -e "${GREEN}==> $1${NC}"
}

warn() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

die() {
    error "$1"
    exit 1
}

# ------------------------------------------------------------
# Root / environment checks
# ------------------------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    die "Run this script as root."
fi

if [[ ! -d /sys/firmware/efi ]]; then
    die "System was not booted in UEFI mode."
fi

if [[ ! -b "$DISK" ]]; then
    die "$DISK does not exist."
fi

if ! ping -c 1 -W 3 artixlinux.org >/dev/null 2>&1; then
    die "Network connectivity test failed. Connect Ethernet and try again."
fi

echo
echo "============================================================"
echo "        ARTIX LINUX INSTALLER"
echo "============================================================"
echo
echo "THIS WILL COMPLETELY ERASE:"
echo
echo "    $DISK"
echo
echo "The target configuration is:"
echo
echo "    UEFI / GPT"
echo "    EFI       1 GiB"
echo "    Btrfs     remaining space"
echo "    OpenRC"
echo "    XLibre"
echo "    Qtile"
echo "    LightDM"
echo "    AMD RX 7900 XT"
echo
echo "User:"
echo "    $USERNAME"
echo
echo "Hostname:"
echo "    $HOSTNAME"
echo
echo "Timezone:"
echo "    $TIMEZONE"
echo
echo "============================================================"
echo

read -r -p "Type ERASE to continue: " CONFIRM

if [[ "$CONFIRM" != "ERASE" ]]; then
    die "Installation cancelled."
fi

# ------------------------------------------------------------
# Make sure nothing is mounted under /mnt
# ------------------------------------------------------------

info "Unmounting anything currently mounted under /mnt..."

umount -R "$MNT" 2>/dev/null || true

# ------------------------------------------------------------
# Partition disk
# ------------------------------------------------------------

info "Wiping existing filesystem signatures..."

wipefs -af "$DISK"

info "Creating GPT partition table..."

sfdisk "$DISK" <<'EOF'
label: gpt
unit: MiB

start=1, size=1024, type=U
start=1025, type=83
EOF

partprobe "$DISK"
sleep 2

EFI="${DISK}p1"
ROOT="${DISK}p2"

if [[ ! -b "$EFI" || ! -b "$ROOT" ]]; then
    die "Partition devices were not created correctly."
fi

# ------------------------------------------------------------
# Format
# ------------------------------------------------------------

info "Formatting EFI partition..."

mkfs.fat -F32 "$EFI"

info "Formatting Btrfs root partition..."

mkfs.btrfs -f "$ROOT"

# ------------------------------------------------------------
# Create Btrfs subvolumes
# ------------------------------------------------------------

info "Creating Btrfs subvolumes..."

mount "$ROOT" "$MNT"

btrfs subvolume create "$MNT/@"
btrfs subvolume create "$MNT/@home"
btrfs subvolume create "$MNT/@log"
btrfs subvolume create "$MNT/@cache"

umount "$MNT"

# ------------------------------------------------------------
# Mount Btrfs subvolumes
# ------------------------------------------------------------

info "Mounting Btrfs subvolumes..."

mount -o subvol=@,compress=zstd,noatime "$ROOT" "$MNT"

mkdir -p \
    "$MNT/home" \
    "$MNT/var/log" \
    "$MNT/var/cache" \
    "$MNT/boot/efi"

mount -o subvol=@home,compress=zstd,noatime "$ROOT" "$MNT/home"
mount -o subvol=@log,compress=zstd,noatime "$ROOT" "$MNT/var/log"
mount -o subvol=@cache,compress=zstd,noatime "$ROOT" "$MNT/var/cache"

mount "$EFI" "$MNT/boot/efi"

info "Current mounts:"

mount | grep "$MNT" || true

# ------------------------------------------------------------
# DNS for chroot
# ------------------------------------------------------------

info "Preparing DNS for the new system..."

rm -f "$MNT/etc/resolv.conf"
cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"

# ------------------------------------------------------------
# Install base system
# ------------------------------------------------------------

info "Installing Artix base system..."

basestrap "$MNT" \
    base \
    base-devel \
    linux \
    linux-firmware \
    amd-ucode \
    openrc \
    elogind \
    elogind-openrc \
    btrfs-progs \
    efibootmgr \
    grub \
    nano \
    vim \
    curl \
    wget \
    git \
    sudo \
    networkmanager \
    networkmanager-openrc

# ------------------------------------------------------------
# Create fstab manually
# ------------------------------------------------------------

info "Creating fstab..."

ROOT_UUID="$(blkid -s UUID -o value "$ROOT")"
EFI_UUID="$(blkid -s UUID -o value "$EFI")"

cat > "$MNT/etc/fstab" <<EOF
# Btrfs root
UUID=$ROOT_UUID  /          btrfs  subvol=@,compress=zstd,noatime  0 0

# Btrfs home
UUID=$ROOT_UUID  /home      btrfs  subvol=@home,compress=zstd,noatime  0 0

# Btrfs logs
UUID=$ROOT_UUID  /var/log   btrfs  subvol=@log,compress=zstd,noatime  0 0

# Btrfs cache
UUID=$ROOT_UUID  /var/cache btrfs  subvol=@cache,compress=zstd,noatime  0 0

# EFI
UUID=$EFI_UUID   /boot/efi  vfat   umask=0077  0 2
EOF

cat "$MNT/etc/fstab"

# ------------------------------------------------------------
# Copy chroot installer
# ------------------------------------------------------------

info "Creating chroot installation script..."

cat > "$MNT$CHROOT_SCRIPT" <<'CHROOT_SCRIPT'
#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() {
    echo -e "${CYAN}==> $1${NC}"
}

success() {
    echo -e "${GREEN}==> $1${NC}"
}

warn() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

die() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

HOSTNAME="artix"
USERNAME="mike"
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"

# ============================================================
# Base configuration
# ============================================================

info "Configuring timezone..."

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

info "Configuring locale..."

sed -i "s/^#\(${LOCALE} UTF-8\)/\1/" /etc/locale.gen

locale-gen

cat > /etc/locale.conf <<EOF
LANG=$LOCALE
EOF

info "Configuring hostname..."

echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# ============================================================
# Arch Linux repository support
# ============================================================

info "Installing Artix Arch Linux repository support..."

pacman -S --needed --noconfirm artix-archlinux-support

info "Enabling Arch Linux repositories..."

cat >> /etc/pacman.conf <<'EOF'

# ============================================================
# Arch Linux repositories
#
# Keep these BELOW the Artix repositories.
# Artix packages take precedence where both provide a package.
# ============================================================

[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF

info "Populating Arch Linux keys..."

pacman-key --populate archlinux

info "Synchronizing repositories..."

pacman -Syy

info "Performing full system upgrade..."

pacman -Syu --noconfirm

# ============================================================
# XLibre repository
# ============================================================

info "Installing XLibre repository signing tools..."

pacman -S --needed --noconfirm curl

info "Installing XLibre Artix signing key..."

curl -fsSL \
    https://xlibre-artix.github.io/xlibre-artixlinux.asc \
    -o /tmp/xlibre-artixlinux.asc

pacman-key --add /tmp/xlibre-artixlinux.asc

pacman-key --finger 2AFFCD7B42ADD2E7

pacman-key --lsign-key 2AFFCD7B42ADD2E7

rm -f /tmp/xlibre-artixlinux.asc

info "Adding XLibre stable repository..."

# The XLibre repository must be after [system] but before [world].
# Insert it immediately before the [world] repository.

if ! grep -q '^\[xlibre-stable\]' /etc/pacman.conf; then
    sed -i '/^\[world\]/i\
[xlibre-stable]\
Server = https://github.com/xlibre-artix/stable/releases/download/$arch\
' /etc/pacman.conf
fi

info "Synchronizing XLibre repository..."

pacman -Syy

# ============================================================
# User
# ============================================================

info "Creating user account: $USERNAME"

if ! id "$USERNAME" >/dev/null 2>&1; then
    useradd -m -G wheel,video,audio -s /bin/bash "$USERNAME"
fi

echo
echo "============================================================"
echo "Set the password for user: $USERNAME"
echo "============================================================"
echo

passwd "$USERNAME"

# ============================================================
# Sudo
# ============================================================

info "Configuring normal password-protected sudo..."

# Remove any existing wheel rule we may have created previously.
sed -i '/^[[:space:]]*%wheel[[:space:]]\+ALL=(ALL:ALL)[[:space:]]\+ALL/d' /etc/sudoers

# Remove any accidental NOPASSWD wheel rule.
sed -i '/^[[:space:]]*%wheel[[:space:]]\+ALL=(ALL:ALL)[[:space:]]\+NOPASSWD:/d' /etc/sudoers

# Add normal wheel sudo permission.
cat >> /etc/sudoers <<'EOF'

# Allow wheel group to use sudo with password authentication.
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 440 /etc/sudoers

# ============================================================
# Core desktop / services
# ============================================================

info "Installing desktop and system packages..."

pacman -S --needed --noconfirm \
    dbus \
    dbus-openrc \
    polkit \
    polkit-gnome \
    networkmanager \
    networkmanager-openrc \
    elogind \
    elogind-openrc \
    lightdm \
    lightdm-gtk-greeter \
    lightdm-openrc \
    qtile \
    python-psutil \
    alacritty \
    rofi \
    dunst \
    picom \
    thunar \
    git \
    neovim \
    tmux \
    wget \
    curl \
    xorg-xrandr \
    xorg-xset \
    xorg-xsetroot \
    xorg-xmodmap \
    xorg-xinit \
    xorg-xdpyinfo

# ============================================================
# XLibre
# ============================================================

info "Installing XLibre..."

pacman -S --needed --noconfirm \
    xlibre-meta \
    xlibre-xf86-video-amdgpu \
    xlibre-xf86-input-libinput

# ============================================================
# AMD graphics / Vulkan
# ============================================================

info "Installing AMD graphics stack..."

pacman -S --needed --noconfirm \
    mesa \
    lib32-mesa \
    vulkan-radeon \
    lib32-vulkan-radeon \
    vulkan-icd-loader \
    lib32-vulkan-icd-loader \
    libva-mesa-driver \
    mesa-vdpau

# ============================================================
# PipeWire
# ============================================================

info "Installing PipeWire..."

pacman -S --needed --noconfirm \
    pipewire \
    pipewire-pulse \
    wireplumber \
    alsa-utils

# ============================================================
# Bluetooth
# ============================================================

info "Installing Bluetooth..."

pacman -S --needed --noconfirm \
    bluez \
    bluez-utils \
    blueman \
    bluez-openrc

# ============================================================
# Flatpak + XDG portals
# ============================================================

info "Installing Flatpak and XDG portals..."

pacman -S --needed --noconfirm \
    flatpak \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk

# ============================================================
# ZarisWM development environment
# ============================================================

info "Installing ZarisWM development tools..."

pacman -S --needed --noconfirm \
    base-devel \
    gcc \
    make \
    cmake \
    meson \
    ninja \
    pkgconf \
    python \
    python-pip \
    python-setuptools \
    libx11 \
    libxft \
    libxinerama \
    libxrandr \
    libxrender \
    libxcb \
    xcb-util \
    xcb-util-wm \
    xcb-util-keysyms \
    xcb-util-renderutil

# ============================================================
# LightDM
# ============================================================

info "Configuring LightDM..."

mkdir -p /etc/lightdm

if [[ -f /etc/lightdm/lightdm.conf ]]; then
    if ! grep -q '^greeter-session=lightdm-gtk-greeter' /etc/lightdm/lightdm.conf; then
        cat >> /etc/lightdm/lightdm.conf <<'EOF'

[Seat:*]
greeter-session=lightdm-gtk-greeter
EOF
    fi
else
    cat > /etc/lightdm/lightdm.conf <<'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
EOF
fi

# ============================================================
# Qtile X11 session
# ============================================================

info "Creating Qtile X11 session..."

mkdir -p /usr/share/xsessions

cat > /usr/share/xsessions/qtile.desktop <<'EOF'
[Desktop Entry]
Name=Qtile
Comment=Qtile X11 Session
Exec=qtile start
Type=Application
Keywords=wm;tiling
EOF

# ============================================================
# Basic Qtile configuration
# ============================================================

info "Creating a minimal Qtile configuration..."

mkdir -p "/home/$USERNAME/.config/qtile"

cat > "/home/$USERNAME/.config/qtile/config.py" <<'EOF'
from libqtile import bar, layout, qtile, widget
from libqtile.config import Key, Group
from libqtile.lazy import lazy

mod = "mod4"

keys = [
    Key([mod], "Return", lazy.spawn("alacritty")),
    Key([mod], "d", lazy.spawn("rofi -show drun")),

    Key([mod], "q", lazy.window.kill()),

    Key([mod, "control"], "r", lazy.reload_config()),
    Key([mod, "control"], "q", lazy.shutdown()),

    Key([mod], "h", lazy.layout.left()),
    Key([mod], "l", lazy.layout.right()),
    Key([mod], "j", lazy.layout.down()),
    Key([mod], "k", lazy.layout.up()),

    Key([mod, "shift"], "h", lazy.layout.shuffle_left()),
    Key([mod, "shift"], "l", lazy.layout.shuffle_right()),
    Key([mod, "shift"], "j", lazy.layout.shuffle_down()),
    Key([mod, "shift"], "k", lazy.layout.shuffle_up()),
]

groups = [
    Group("1"),
    Group("2"),
    Group("3"),
    Group("4"),
    Group("5"),
    Group("6"),
    Group("7"),
    Group("8"),
    Group("9"),
    Group("0"),
]

for i, group in enumerate(groups):
    keys.append(
        Key([mod], str(i + 1 if i < 9 else 0),
            lazy.group[group.name].toscreen())
    )

layouts = [
    layout.MonadTall(
        border_width=2,
        margin=8,
    ),
    layout.Max(),
]

widget_defaults = dict(
    font="sans",
    fontsize=14,
    padding=3,
)

screens = [
    Screen(
        top=bar.Bar(
            [
                widget.GroupBox(),
                widget.Spacer(),
                widget.Clock(format="%Y-%m-%d %H:%M"),
            ],
            24,
        ),
    ),
]

floating_layout = layout.Floating()
auto_fullscreen = True
focus_on_window_activation = "smart"
wmname = "LG3D"
EOF

chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.config"

# ============================================================
# OpenRC services
# ============================================================

info "Enabling OpenRC services..."

rc-update add networkmanager default
rc-update add dbus default
rc-update add lightdm default
rc-update add bluetooth default
rc-update add elogind boot

# ============================================================
# Flatpak / Flathub
# ============================================================

info "Adding Flathub..."

flatpak remote-add --if-not-exists \
    flathub \
    https://flathub.org/repo/flathub.flatpakrepo

# ============================================================
# GRUB
# ============================================================

info "Installing GRUB..."

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=Artix

grub-mkconfig -o /boot/grub/grub.cfg

# ============================================================
# Final ownership / permissions
# ============================================================

chown "$USERNAME:$USERNAME" "/home/$USERNAME"

# ============================================================
# Verification
# ============================================================

echo
echo "============================================================"
echo "Installation checks"
echo "============================================================"

echo
echo "User:"
id "$USERNAME"

echo
echo "Btrfs:"
findmnt -t btrfs

echo
echo "EFI:"
findmnt /boot/efi

echo
echo "OpenRC services:"
rc-status --all || true

echo
echo "Arch repositories:"
grep -A2 -E '^\[(extra|multilib)\]' /etc/pacman.conf || true

echo
echo "XLibre:"
pacman -Q | grep -E '^xlibre' || true

echo
echo "Qtile:"
pacman -Q qtile || true

echo
echo "============================================================"
echo "Installation inside chroot is complete."
echo "============================================================"
echo
echo "The root account password was NOT configured."
echo "The user account '$USERNAME' has a password."
echo "sudo requires the '$USERNAME' password."
echo
echo "Exit the chroot and reboot from the live environment."
echo
CHROOT_SCRIPT

chmod +x "$MNT$CHROOT_SCRIPT"

# ------------------------------------------------------------
# Run chroot installation
# ------------------------------------------------------------

info "Entering the new Artix installation..."

artix-chroot "$MNT" /root/artix-chroot-install.sh

# ------------------------------------------------------------
# Clean up
# ------------------------------------------------------------

info "Removing temporary chroot installer..."

rm -f "$MNT$CHROOT_SCRIPT"

# Restore resolv.conf as a normal symlink for the installed system.
rm -f "$MNT/etc/resolv.conf"

if [[ -e /mnt/run/systemd/resolve/stub-resolv.conf ]]; then
    ln -s /run/systemd/resolve/stub-resolv.conf "$MNT/etc/resolv.conf"
fi

# ------------------------------------------------------------
# Final information
# ------------------------------------------------------------

success "Artix installation completed."

echo
echo "============================================================"
echo "                  INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Installed:"
echo
echo "  Artix Linux"
echo "  OpenRC"
echo "  Btrfs"
echo "  GRUB / UEFI"
echo "  NetworkManager"
echo "  elogind"
echo "  XLibre"
echo "  AMDGPU"
echo "  Qtile"
echo "  LightDM"
echo "  PipeWire"
echo "  Bluetooth"
echo "  Flatpak"
echo "  XDG Desktop Portals"
echo "  Rofi"
echo "  Dunst"
echo "  Picom"
echo "  Thunar"
echo "  Alacritty"
echo
echo "User:     $USERNAME"
echo "Hostname: $HOSTNAME"
echo
echo "IMPORTANT:"
echo "The root account password was not configured."
echo "Your '$USERNAME' account has normal password-protected sudo."
echo
echo "Unmounting filesystems..."
echo

umount -R "$MNT"

echo
success "You can now reboot."
echo
echo "Remove the Artix USB when the system restarts."
echo
read -r -p "Press Enter to reboot, or Ctrl+C to remain in the live environment..."

reboot
