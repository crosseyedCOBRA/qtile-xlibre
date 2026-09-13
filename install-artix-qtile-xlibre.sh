#!/bin/bash
set -euo pipefail

# Artix Linux OpenRC + XLibre + LightDM + Qtile
# UEFI / GPT / XFS / /dev/nvme0n1
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

fail() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Run as root."
[[ -d /sys/firmware/efi ]] || fail "Not booted in UEFI mode. Reboot the USB using its UEFI entry."
[[ -b "$TARGET_DISK" ]] || fail "$TARGET_DISK not found."

ping -c1 -W3 artixlinux.org >/dev/null 2>&1 || fail "No network connectivity."

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

# Passwords are intentionally entered inside the target chroot.

umount -R "$MNT" 2>/dev/null || true
swapoff -a 2>/dev/null || true

# Partition disk.
wipefs -af "$TARGET_DISK"
sgdisk --zap-all "$TARGET_DISK"
sgdisk -n 1:1MiB:+512MiB -t 1:ef00 "$TARGET_DISK"
sgdisk -n 2:0:0 -t 2:8300 "$TARGET_DISK"
partprobe "$TARGET_DISK"
sleep 2

mkfs.fat -F32 "$EFI_PART"
mkfs.xfs -f "$ROOT_PART"

mount "$ROOT_PART" "$MNT"
mkdir -p "$MNT/boot/efi"
mount "$EFI_PART" "$MNT/boot/efi"

# Base Artix system.
basestrap "$MNT" \
  base base-devel linux linux-firmware amd-ucode \
  openrc elogind elogind-openrc dbus dbus-openrc \
  xfsprogs grub efibootmgr \
  networkmanager networkmanager-openrc \
  sudo curl wget nano git

fstabgen -U "$MNT" > "$MNT/etc/fstab"

cat > "$MNT/root/install-vars" <<EOFV
HOSTNAME=$(printf '%q' "$HOSTNAME")
USERNAME=$(printf '%q' "$USERNAME")
TIMEZONE=$(printf '%q' "$TIMEZONE")
KEYMAP=$(printf '%q' "$KEYMAP")
LOCALE=$(printf '%q' "$LOCALE_DEFAULT")
EOFV

cat > "$MNT/root/configure-artix.sh" <<'CHROOT'
#!/bin/bash
set -euo pipefail
source /root/install-vars

# Locale/time/hostname.
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

# Configure the Artix XLibre repository.
# IMPORTANT: it must be after [system] and before [world].
XLL_KEY=/root/xlibre-artixlinux.asc
curl -fsSL https://xlibre-artix.github.io/xlibre-artixlinux.asc -o "$XLL_KEY"
pacman-key --init
pacman-key --populate artix
pacman-key --add "$XLL_KEY"
pacman-key --finger 2AFFCD7B42ADD2E7
pacman-key --lsign-key 2AFFCD7B42ADD2E7

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

# Sync and perform one complete upgrade. Avoid partial upgrades.
pacman -Syyu --noconfirm

# XLibre meta-package replaces the corresponding X.Org server/input pieces.
pacman -S --needed --noconfirm \
  xlibre-meta \
  xlibre-video-amdgpu \
  xorg-xdpyinfo xorg-xrandr xorg-xset xorg-xsetroot \
  xorg-xmodmap xorg-xev xorg-xprop xclip

# Qtile + LightDM + useful X11 desktop utilities.
pacman -S --needed --noconfirm \
  qtile python-psutil alacritty \
  lightdm lightdm-gtk-greeter lightdm-openrc \
  rofi dunst picom feh thunar pavucontrol flameshot

# Audio. PipeWire itself is user-session based; no fake system service is enabled.
pacman -S --needed --noconfirm \
  pipewire pipewire-audio pipewire-pulse pipewire-alsa wireplumber rtkit

# Networking/Bluetooth.
pacman -S --needed --noconfirm \
  networkmanager networkmanager-openrc bluez bluez-utils blueman

# Desktop portals/Flatpak.
pacman -S --needed --noconfirm \
  flatpak xdg-desktop-portal xdg-desktop-portal-gtk

# Gaming/streaming/editing.
pacman -S --needed --noconfirm \
  steam obs-studio kdenlive

# Utilities/fonts/build tools.
pacman -S --needed --noconfirm \
  noto-fonts noto-fonts-emoji ttf-dejavu ttf-liberation ttf-jetbrains-mono \
  fastfetch btop unzip zip p7zip gcc make cmake pkgconf

# User.
if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd -m -G wheel,networkmanager,audio,video -s /bin/bash "$USERNAME"
fi

echo "Set root password:"
passwd root
echo "Set password for $USERNAME:"
passwd "$USERNAME"

# sudo wheel access.
if grep -q '^# %wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
  sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
fi

# Qtile session for LightDM.
install -d /usr/share/xsessions
cat > /usr/share/xsessions/qtile.desktop <<'EOFSESSION'
[Desktop Entry]
Name=Qtile
Comment=Qtile Tiling Window Manager
Exec=qtile start
Type=Application
Keywords=wm;tiling
EOFSESSION

cat > /etc/lightdm/lightdm.conf <<'EOFLIGHT'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=qtile
EOFLIGHT

# Minimal starter Qtile config. User can replace it later with their real config.
install -d -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.config/qtile"
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

layouts = [layout.Monadtall(), layout.Max()]
widget_defaults = dict(font="JetBrains Mono", fontsize=14, padding=3)

screens = [Screen(top=bar.Bar([
    widget.GroupBox(), widget.WindowName(), widget.Clock(format="%Y-%m-%d %H:%M")
], 24))]

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
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.config"

# OpenRC services.
rc-update add NetworkManager default || true
rc-update add elogind boot || true
rc-update add dbus default || true
rc-update add lightdm default || true
# bluetooth is provided by bluez; enable it if the installed OpenRC service exists.
if rc-service bluetooth status >/dev/null 2>&1 || [[ -x /etc/init.d/bluetooth ]]; then
  rc-update add bluetooth default || true
fi

# GRUB UEFI.
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Artix --recheck
grub-mkconfig -o /boot/grub/grub.cfg
mkinitcpio -P

# XLibre verification helper for after first login.
cat > /usr/local/bin/check-xlibre <<'EOFVERIFY'
#!/bin/sh
set -eu
if ! command -v xdpyinfo >/dev/null 2>&1; then
  echo "xdpyinfo is not installed."
  exit 1
fi
xdpyinfo | grep -E 'vendor|X.Org|XLibre' || true
EOFVERIFY
chmod +x /usr/local/bin/check-xlibre

rm -f /root/install-vars /root/configure-artix.sh /root/xlibre-artixlinux.asc

CHROOT

chmod +x "$MNT/root/configure-artix.sh"
artix-chroot "$MNT" /root/configure-artix.sh

sync
umount -R "$MNT"

echo
echo "============================================================"
echo "Installation complete. Remove the USB and reboot."
echo "============================================================"
reboot
