#!/bin/bash

# ============================================================
# Artix Linux OpenRC + Btrfs + XLibre + Qtile
#
# Target: /dev/nvme0n1
# Boot: UEFI / GPT
# Filesystem: Btrfs
# Init: OpenRC
# WM: Qtile
# Display Manager: LightDM GTK
# GPU: AMD RX 7900 XT
# Network: Ethernet
#
# WARNING:
# THIS SCRIPT WILL ERASE /dev/nvme0n1
# ============================================================

DISK="/dev/nvme0n1"
EFI="/dev/nvme0n1p1"
ROOT="/dev/nvme0n1p2"

HOSTNAME="artix"
USERNAME="mike"
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"

MNT="/mnt"

# ------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

if [ ! -d /sys/firmware/efi ]; then
    echo "ERROR: System is not booted in UEFI mode."
    exit 1
fi

if [ ! -b "$DISK" ]; then
    echo "ERROR: $DISK does not exist."
    exit 1
fi

echo
echo "============================================================"
echo "                 ARTIX LINUX INSTALLER"
echo "============================================================"
echo
echo "THIS WILL COMPLETELY ERASE:"
echo
echo "    $DISK"
echo
echo "The installation will contain:"
echo
echo "    UEFI / GPT"
echo "    Btrfs"
echo "    OpenRC"
echo "    XLibre"
echo "    Qtile"
echo "    LightDM"
echo "    NetworkManager"
echo "    PipeWire"
echo "    Bluetooth"
echo "    Flatpak"
echo "    Arch repositories"
echo
echo "User:     $USERNAME"
echo "Hostname: $HOSTNAME"
echo
echo "============================================================"
echo

ping -c 1 -W 3 artixlinux.org >/dev/null 2>&1

if [ $? != 0 ]; then
    echo
    echo "ERROR: Network connectivity test failed."
    echo "Make sure Ethernet is connected."
    exit 1
fi

echo "Network connection: OK"
echo

read -r -p "Type ERASE to continue: " CONFIRM

if [ "$CONFIRM" != "ERASE" ]; then
    echo "Installation cancelled."
    exit 1
fi

# ------------------------------------------------------------
# Unmount anything currently mounted
# ------------------------------------------------------------

echo
echo "==> Unmounting existing /mnt mounts..."

umount -R "$MNT" 2>/dev/null

# ------------------------------------------------------------
# Partition disk
# ------------------------------------------------------------

echo
echo "==> Wiping existing partition/filesystem information..."

wipefs -af "$DISK"

echo
echo "==> Creating GPT partition table..."

sfdisk "$DISK" <<EOF
label: gpt
unit: MiB

start=1, size=1024, type=U
start=1025, type=83
EOF

partprobe "$DISK"

sleep 3

if [ ! -b "$EFI" ]; then
    echo "ERROR: EFI partition was not created."
    exit 1
fi

if [ ! -b "$ROOT" ]; then
    echo "ERROR: Root partition was not created."
    exit 1
fi

# ------------------------------------------------------------
# Format partitions
# ------------------------------------------------------------

echo
echo "==> Formatting EFI partition..."

mkfs.fat -F32 "$EFI"

echo
echo "==> Formatting Btrfs root partition..."

mkfs.btrfs -f "$ROOT"

# ------------------------------------------------------------
# Create Btrfs subvolumes
# ------------------------------------------------------------

echo
echo "==> Creating Btrfs subvolumes..."

mount "$ROOT" "$MNT"

btrfs subvolume create "$MNT/@"
btrfs subvolume create "$MNT/@home"
btrfs subvolume create "$MNT/@log"
btrfs subvolume create "$MNT/@cache"

umount "$MNT"

# ------------------------------------------------------------
# Mount Btrfs
# ------------------------------------------------------------

echo
echo "==> Mounting Btrfs subvolumes..."

mount -o subvol=@,compress=zstd,noatime "$ROOT" "$MNT"

mkdir -p "$MNT/home"
mkdir -p "$MNT/var/log"
mkdir -p "$MNT/var/cache"
mkdir -p "$MNT/boot/efi"

mount -o subvol=@home,compress=zstd,noatime "$ROOT" "$MNT/home"
mount -o subvol=@log,compress=zstd,noatime "$ROOT" "$MNT/var/log"
mount -o subvol=@cache,compress=zstd,noatime "$ROOT" "$MNT/var/cache"

mount "$EFI" "$MNT/boot/efi"

echo
echo "==> Current mounts:"
mount | grep "$MNT"

# ------------------------------------------------------------
# DNS
# ------------------------------------------------------------

echo
echo "==> Setting up DNS for installation..."

cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"

# ------------------------------------------------------------
# Install Artix base
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Installing Artix base system"
echo "============================================================"
echo

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
    grub \
    efibootmgr \
    sudo \
    nano \
    vim \
    git \
    wget \
    curl \
    networkmanager \
    networkmanager-openrc

# ------------------------------------------------------------
# Generate fstab
# ------------------------------------------------------------

echo
echo "==> Generating fstab..."

ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
EFI_UUID=$(blkid -s UUID -o value "$EFI")

cat > "$MNT/etc/fstab" <<EOF
UUID=$ROOT_UUID / btrfs subvol=@,compress=zstd,noatime 0 0
UUID=$ROOT_UUID /home btrfs subvol=@home,compress=zstd,noatime 0 0
UUID=$ROOT_UUID /var/log btrfs subvol=@log,compress=zstd,noatime 0 0
UUID=$ROOT_UUID /var/cache btrfs subvol=@cache,compress=zstd,noatime 0 0
UUID=$EFI_UUID /boot/efi vfat umask=0077 0 2
EOF

echo
echo "==> Generated fstab:"
echo
cat "$MNT/etc/fstab"

# ============================================================
# CHROOT SCRIPT
# ============================================================

echo
echo "==> Creating chroot installation script..."

cat > "$MNT/root/artix-setup.sh" <<'CHROOT'
#!/bin/bash

HOSTNAME="artix"
USERNAME="mike"
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"

echo
echo "============================================================"
echo "       CONFIGURING INSTALLED ARTIX SYSTEM"
echo "============================================================"
echo

# ------------------------------------------------------------
# Timezone
# ------------------------------------------------------------

echo "==> Configuring timezone..."

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

# ------------------------------------------------------------
# Locale
# ------------------------------------------------------------

echo "==> Configuring locale..."

sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen

locale-gen

echo "LANG=$LOCALE" > /etc/locale.conf

# ------------------------------------------------------------
# Hostname
# ------------------------------------------------------------

echo "==> Configuring hostname..."

echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# ------------------------------------------------------------
# Update package databases
# ------------------------------------------------------------

echo
echo "==> Updating Artix package databases..."

pacman -Sy --noconfirm

# ------------------------------------------------------------
# Arch Linux support
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Installing Artix Arch Linux support"
echo "============================================================"
echo

pacman -S --needed --noconfirm artix-archlinux-support

echo
echo "==> Configuring Arch repositories..."

cat >> /etc/pacman.conf <<EOF

# ============================================================
# Arch Linux repositories
# ============================================================

[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF

echo
echo "==> Populating Arch Linux keyring..."

pacman-key --populate archlinux

echo
echo "==> Synchronizing repositories..."

pacman -Syy

echo
echo "==> Performing full system update..."

pacman -Syu --noconfirm

# ------------------------------------------------------------
# XLibre repository
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Configuring XLibre"
echo "============================================================"
echo

pacman -S --needed --noconfirm curl

echo "==> Downloading XLibre signing key..."

curl -fsSL \
    https://xlibre-artix.github.io/xlibre-artixlinux.asc \
    -o /tmp/xlibre-artixlinux.asc

echo "==> Adding XLibre signing key..."

pacman-key --add /tmp/xlibre-artixlinux.asc

echo "==> Checking XLibre key..."

pacman-key --finger 2AFFCD7B42ADD2E7

echo "==> Locally signing XLibre key..."

pacman-key --lsign-key 2AFFCD7B42ADD2E7

rm -f /tmp/xlibre-artixlinux.asc

echo
echo "==> Adding XLibre repository..."

if ! grep -q "^\[xlibre-stable\]" /etc/pacman.conf; then

    sed -i '/^\[world\]/i\
[xlibre-stable]\
Server = https://github.com/xlibre-artix/stable/releases/download/$arch\
' /etc/pacman.conf

fi

echo
echo "==> Synchronizing XLibre repository..."

pacman -Syy

# ------------------------------------------------------------
# User account
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Creating user account"
echo "============================================================"
echo

if id "$USERNAME" >/dev/null 2>&1; then
    echo "User $USERNAME already exists."
else
    useradd -m -G wheel,video,audio -s /bin/bash "$USERNAME"
fi

echo
echo "Set the password for $USERNAME."
echo

passwd "$USERNAME"

# ------------------------------------------------------------
# Sudo
# ------------------------------------------------------------

echo
echo "==> Configuring normal password-protected sudo..."

if ! grep -q "^%wheel ALL=(ALL:ALL) ALL$" /etc/sudoers; then

    cat >> /etc/sudoers <<EOF

# Wheel users may use sudo with their password.
%wheel ALL=(ALL:ALL) ALL
EOF

fi

chmod 440 /etc/sudoers

# ------------------------------------------------------------
# Desktop packages
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Installing desktop packages"
echo "============================================================"
echo

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
    xorg-xinit \
    xorg-xrandr \
    xorg-xset \
    xorg-xsetroot \
    xorg-xmodmap \
    xorg-xdpyinfo

# ------------------------------------------------------------
# XLibre
# ------------------------------------------------------------

echo
echo "==> Installing XLibre..."

pacman -S --needed --noconfirm \
    xlibre-meta \
    xlibre-xf86-video-amdgpu \
    xlibre-xf86-input-libinput

# ------------------------------------------------------------
# AMD graphics
# ------------------------------------------------------------

echo
echo "==> Installing AMD graphics stack..."

pacman -S --needed --noconfirm \
    mesa \
    lib32-mesa \
    vulkan-radeon \
    lib32-vulkan-radeon \
    vulkan-icd-loader \
    lib32-vulkan-icd-loader \
    libva-mesa-driver \
    mesa-vdpau

# ------------------------------------------------------------
# PipeWire
# ------------------------------------------------------------

echo
echo "==> Installing PipeWire..."

pacman -S --needed --noconfirm \
    pipewire \
    pipewire-pulse \
    wireplumber \
    alsa-utils

# ------------------------------------------------------------
# Bluetooth
# ------------------------------------------------------------

echo
echo "==> Installing Bluetooth..."

pacman -S --needed --noconfirm \
    bluez \
    bluez-utils \
    blueman \
    bluez-openrc

# ------------------------------------------------------------
# Flatpak / portals
# ------------------------------------------------------------

echo
echo "==> Installing Flatpak and XDG portals..."

pacman -S --needed --noconfirm \
    flatpak \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk

echo
echo "==> Adding Flathub..."

flatpak remote-add --if-not-exists \
    flathub \
    https://flathub.org/repo/flathub.flatpakrepo

# ------------------------------------------------------------
# ZarisWM development
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Installing development tools"
echo "============================================================"
echo

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

# ------------------------------------------------------------
# LightDM
# ------------------------------------------------------------

echo
echo "==> Configuring LightDM..."

mkdir -p /etc/lightdm

cat > /etc/lightdm/lightdm.conf <<EOF
[Seat:*]
greeter-session=lightdm-gtk-greeter
EOF

# ------------------------------------------------------------
# Qtile session
# ------------------------------------------------------------

echo
echo "==> Creating Qtile session..."

mkdir -p /usr/share/xsessions

cat > /usr/share/xsessions/qtile.desktop <<EOF
[Desktop Entry]
Name=Qtile
Comment=Qtile X11 Session
Exec=qtile start
Type=Application
Keywords=wm;tiling
EOF

# ------------------------------------------------------------
# Basic Qtile config
# ------------------------------------------------------------

echo
echo "==> Creating basic Qtile configuration..."

mkdir -p "/home/$USERNAME/.config/qtile"

cat > "/home/$USERNAME/.config/qtile/config.py" <<'EOF'
from libqtile import bar, layout, widget
from libqtile.config import Key, Group, Screen
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

for group in groups:
    keys.append(
        Key(
            [mod],
            group.name,
            lazy.group[group.name].toscreen()
        )
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

# ------------------------------------------------------------
# OpenRC services
# ------------------------------------------------------------

echo
echo "==> Enabling OpenRC services..."

rc-update add networkmanager default
rc-update add dbus default
rc-update add lightdm default
rc-update add bluetooth default
rc-update add elogind boot

# ------------------------------------------------------------
# GRUB
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Installing GRUB"
echo "============================================================"
echo

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=Artix

grub-mkconfig -o /boot/grub/grub.cfg

# ------------------------------------------------------------
# Final checks
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                 INSTALLATION CHECK"
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
echo "Qtile:"
pacman -Q qtile

echo
echo "XLibre packages:"
pacman -Q | grep "^xlibre" || true

echo
echo "Arch repositories:"
grep -A2 -E "^\[(extra|multilib)\]" /etc/pacman.conf || true

echo
echo "OpenRC services:"
rc-status --all || true

echo
echo "============================================================"
echo "             CHROOT INSTALLATION COMPLETE"
echo "============================================================"
echo

rm -f /root/artix-setup.sh

CHROOT

chmod +x "$MNT/root/artix-setup.sh"

# ------------------------------------------------------------
# Enter chroot
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Entering installed Artix system"
echo "============================================================"
echo

artix-chroot "$MNT" /root/artix-setup.sh

# ------------------------------------------------------------
# Clean up
# ------------------------------------------------------------

echo
echo "==> Cleaning up..."

rm -f "$MNT/root/artix-setup.sh"

sync

echo
echo "==> Unmounting installed system..."

umount -R "$MNT"

sync

echo
echo "============================================================"
echo "             ARTIX INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "User:     $USERNAME"
echo "Hostname: $HOSTNAME"
echo
echo "The root account password was NOT configured."
echo
echo "The user account '$USERNAME' has a password."
echo "sudo requires that password."
echo
echo "Installed:"
echo
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
echo "  Arch extra"
echo "  Arch multilib"
echo
echo "Remove the Artix USB and reboot."
echo

read -r -p "Press Enter to reboot..."

reboot
