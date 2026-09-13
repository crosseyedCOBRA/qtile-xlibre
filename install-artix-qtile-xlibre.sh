#!/bin/bash

set -euo pipefail

###############################################################################
# Artix Linux + OpenRC + XLibre + Custom dwm
#
# UEFI / GPT / XFS
# Target: /dev/nvme0n1
#
# WARNING:
# THIS SCRIPT ERASES THE TARGET DISK.
###############################################################################

TARGET_DISK="/dev/nvme0n1"
MOUNTPOINT="/mnt"

EFI_PART="${TARGET_DISK}p1"
ROOT_PART="${TARGET_DISK}p2"

DEFAULT_USERNAME="mike"
DEFAULT_HOSTNAME="artix"
DEFAULT_TIMEZONE="America/New_York"
DEFAULT_KEYMAP="us"
DEFAULT_LOCALE="en_US.UTF-8"

DWM_VERSION="6.6"
DWM_URL="https://dl.suckless.org/dwm/dwm-${DWM_VERSION}.tar.gz"

###############################################################################
# Helpers
###############################################################################

die() {
    echo
    echo "ERROR: $1"
    exit 1
}

msg() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

###############################################################################
# Initial checks
###############################################################################

if [[ "$EUID" -ne 0 ]]; then
    die "Run this script as root."
fi

if [[ ! -d /sys/firmware/efi ]]; then
    die "System is not booted in UEFI mode."
fi

if [[ ! -b "$TARGET_DISK" ]]; then
    die "Target disk $TARGET_DISK does not exist."
fi

msg "Artix Linux + XLibre + Custom dwm Installer"

echo "Target disk : $TARGET_DISK"
echo "Hostname    : $DEFAULT_HOSTNAME"
echo "Username    : $DEFAULT_USERNAME"
echo "Timezone    : $DEFAULT_TIMEZONE"
echo "Keyboard    : $DEFAULT_KEYMAP"
echo "Locale      : $DEFAULT_LOCALE"
echo
echo "Desktop     : dwm"
echo "Display     : XLibre"
echo "Init        : OpenRC"
echo "Filesystem  : XFS"
echo

if ! ping -c 1 -W 3 artixlinux.org >/dev/null 2>&1; then
    die "No network connection."
fi

###############################################################################
# User configuration
###############################################################################

read -rp "Hostname [$DEFAULT_HOSTNAME]: " HOSTNAME
HOSTNAME="${HOSTNAME:-$DEFAULT_HOSTNAME}"

read -rp "Username [$DEFAULT_USERNAME]: " USERNAME
USERNAME="${USERNAME:-$DEFAULT_USERNAME}"

read -rp "Timezone [$DEFAULT_TIMEZONE]: " TIMEZONE
TIMEZONE="${TIMEZONE:-$DEFAULT_TIMEZONE}"

read -rp "Keyboard [$DEFAULT_KEYMAP]: " KEYMAP
KEYMAP="${KEYMAP:-$DEFAULT_KEYMAP}"

read -rp "Locale [$DEFAULT_LOCALE]: " LOCALE
LOCALE="${LOCALE:-$DEFAULT_LOCALE}"

echo
echo "Set password for user '$USERNAME'."
echo

read -rsp "Password: " USER_PASSWORD
echo

read -rsp "Confirm password: " USER_PASSWORD_CONFIRM
echo

if [[ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]]; then
    die "Passwords do not match."
fi

if [[ -z "$USER_PASSWORD" ]]; then
    die "Password cannot be empty."
fi

###############################################################################
# Final confirmation
###############################################################################

echo
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "THIS WILL ERASE:"
echo "    $TARGET_DISK"
echo
echo "ALL DATA ON THIS DISK WILL BE DESTROYED."
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo

read -rp "Type ERASE to continue: " CONFIRM

if [[ "$CONFIRM" != "ERASE" ]]; then
    die "Installation cancelled."
fi

###############################################################################
# Live environment packages
###############################################################################

msg "Installing live environment tools"

pacman -Sy --noconfirm \
    gptfdisk \
    parted \
    git

###############################################################################
# Disk preparation
###############################################################################

msg "Wiping $TARGET_DISK"

umount -R "$MOUNTPOINT" 2>/dev/null || true

wipefs -af "$TARGET_DISK"

sgdisk --zap-all "$TARGET_DISK"

sgdisk \
    -n 1:1MiB:+512MiB \
    -t 1:ef00 \
    -c 1:"EFI System Partition" \
    -n 2:0:0 \
    -t 2:8300 \
    -c 2:"Artix Root" \
    "$TARGET_DISK"

partprobe "$TARGET_DISK"

sleep 2

###############################################################################
# Filesystems
###############################################################################

msg "Formatting filesystems"

mkfs.fat -F32 "$EFI_PART"

mkfs.xfs -f "$ROOT_PART"

###############################################################################
# Mount
###############################################################################

msg "Mounting target filesystem"

mount "$ROOT_PART" "$MOUNTPOINT"

mkdir -p "$MOUNTPOINT/boot/efi"

mount "$EFI_PART" "$MOUNTPOINT/boot/efi"

###############################################################################
# Base Artix installation
###############################################################################

msg "Installing Artix base system"

basestrap "$MOUNTPOINT" \
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
# fstab
###############################################################################

msg "Generating fstab"

fstabgen -U "$MOUNTPOINT" >> "$MOUNTPOINT/etc/fstab"

###############################################################################
# Installation variables
###############################################################################

cat > "$MOUNTPOINT/root/install-vars" <<EOF
HOSTNAME='$HOSTNAME'
USERNAME='$USERNAME'
TIMEZONE='$TIMEZONE'
KEYMAP='$KEYMAP'
LOCALE='$LOCALE'
DWM_VERSION='$DWM_VERSION'
DWM_URL='$DWM_URL'
EOF

chmod 600 "$MOUNTPOINT/root/install-vars"

###############################################################################
# Temporary password
###############################################################################

printf '%s' "$USER_PASSWORD" > "$MOUNTPOINT/root/user-password"

chmod 600 "$MOUNTPOINT/root/user-password"

unset USER_PASSWORD
unset USER_PASSWORD_CONFIRM

###############################################################################
# Chroot installer
###############################################################################

cat > "$MOUNTPOINT/root/install-chroot.sh" <<'CHROOT_SCRIPT'
#!/bin/bash

set -euo pipefail

source /root/install-vars

PASSWORD_FILE="/root/user-password"

###############################################################################
# Helpers
###############################################################################

die() {
    echo
    echo "CHROOT ERROR: $1"
    exit 1
}

msg() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

###############################################################################
# Timezone
###############################################################################

msg "Configuring timezone"

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime

hwclock --systohc

###############################################################################
# Locale
###############################################################################

msg "Configuring locale"

if ! grep -q "^${LOCALE} UTF-8" /etc/locale.gen; then
    echo "${LOCALE} UTF-8" >> /etc/locale.gen
fi

sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen

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

echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

###############################################################################
# XLibre repository
###############################################################################

msg "Configuring XLibre repository"

if ! grep -q "^\[xlibre-stable\]" /etc/pacman.conf; then
    sed -i \
        '/^\[world\]/i\
[xlibre-stable]\
Server = https://github.com/xlibre-artix/stable/releases/download/$arch\
' \
        /etc/pacman.conf
fi

###############################################################################
# Arch repositories
###############################################################################

msg "Configuring Arch package support"

pacman -S --noconfirm artix-archlinux-support

###############################################################################
# Repository refresh
###############################################################################

msg "Refreshing package databases"

pacman -Syy --noconfirm

###############################################################################
# Preflight package check
###############################################################################

msg "Checking required packages"

REQUIRED_PACKAGES=(
    xlibre-meta
    xlibre-video-amdgpu

    lightdm
    lightdm-gtk-greeter

    alacritty
    rofi
    dunst
    picom
    feh
    thunar
    pavucontrol
    flameshot

    pipewire
    pipewire-pulse
    pipewire-alsa
    wireplumber

    connman
    connman-openrc

    bluez
    bluez-openrc
    bluez-utils

    flatpak
    xdg-desktop-portal
    xdg-desktop-portal-gtk

    i3lock
    wmctrl

    libx11
    libxft
    libxinerama
    xorgproto
    fontconfig
    freetype2
)

for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! pacman -Si "$package" >/dev/null 2>&1; then
        die "Required package is unavailable: $package"
    fi
done

echo "Preflight package check passed."

###############################################################################
# System update
###############################################################################

msg "Updating system"

pacman -Su --noconfirm

###############################################################################
# XLibre
###############################################################################

msg "Installing XLibre"

pacman -S --noconfirm \
    xlibre-meta \
    xlibre-video-amdgpu \
    xorg-xrandr \
    xorg-xdpyinfo

###############################################################################
# Desktop utilities
###############################################################################

msg "Installing desktop utilities"

pacman -S --noconfirm \
    lightdm \
    lightdm-gtk-greeter \
    alacritty \
    rofi \
    dunst \
    picom \
    feh \
    thunar \
    pavucontrol \
    flameshot \
    i3lock \
    wmctrl

###############################################################################
# PipeWire
###############################################################################

msg "Installing PipeWire"

pacman -S --noconfirm \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    rtkit

###############################################################################
# Networking / Bluetooth
###############################################################################

msg "Installing networking and Bluetooth"

pacman -S --noconfirm \
    connman \
    connman-openrc \
    bluez \
    bluez-openrc \
    bluez-utils

###############################################################################
# Flatpak
###############################################################################

msg "Installing Flatpak"

pacman -S --noconfirm \
    flatpak \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk

###############################################################################
# Fonts
###############################################################################

msg "Installing fonts"

pacman -S --noconfirm \
    noto-fonts \
    noto-fonts-emoji \
    ttf-dejavu \
    ttf-liberation

###############################################################################
# Dwm build dependencies
###############################################################################

msg "Installing dwm build dependencies"

pacman -S --noconfirm \
    base-devel \
    libx11 \
    libxft \
    libxinerama \
    xorgproto \
    fontconfig \
    freetype2

###############################################################################
# Build custom dwm
###############################################################################

msg "Downloading dwm ${DWM_VERSION}"

mkdir -p /usr/local/src

cd /usr/local/src

rm -rf "dwm-${DWM_VERSION}"
rm -f "dwm-${DWM_VERSION}.tar.gz"

curl -fL \
    "$DWM_URL" \
    -o "dwm-${DWM_VERSION}.tar.gz"

tar -xzf "dwm-${DWM_VERSION}.tar.gz"

cd "dwm-${DWM_VERSION}"

###############################################################################
# Custom dwm configuration
###############################################################################

msg "Creating custom dwm configuration"

cat > config.h <<'DWM_CONFIG'
/* See LICENSE file for copyright and license details. */

/* appearance */

static const unsigned int borderpx  = 1;
static const unsigned int snap      = 32;
static const int showbar            = 1;
static const int topbar             = 1;

static const char *fonts[] = {
    "monospace:size=10"
};

static const char dmenufont[] = "monospace:size=10";

static const char col_gray1[] = "#222222";
static const char col_gray2[] = "#444444";
static const char col_gray3[] = "#bbbbbb";
static const char col_gray4[] = "#eeeeee";
static const char col_cyan[]  = "#005577";

static const char *colors[][3] = {
    [SchemeNorm] = { col_gray3, col_gray1, col_gray2 },
    [SchemeSel]  = { col_gray4, col_cyan,  col_cyan  },
};

/* tags */

static const char *tags[] = {
    "1", "2", "3", "4", "5",
    "6", "7", "8", "9"
};

static const Rule rules[] = {
    /* class      instance    title       tags mask     isfloating   monitor */
};

/* layout */

static const float mfact     = 0.55;
static const int nmaster     = 1;
static const int resizehints = 1;

static const Layout layouts[] = {
    { "[]=",      tile },
    { "><>",      NULL },
    { "[M]",      monocle },
};

/* commands */

#define MODKEY Mod4Mask

#define TAGKEYS(KEY,TAG) \
    { MODKEY,                       KEY, view,       {.ui = 1 << TAG} }, \
    { MODKEY|ControlMask,           KEY, toggleview, {.ui = 1 << TAG} }, \
    { MODKEY|ShiftMask,             KEY, tag,        {.ui = 1 << TAG} }, \
    { MODKEY|ControlMask|ShiftMask, KEY, toggletag,  {.ui = 1 << TAG} },

#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

/* applications */

static const char *termcmd[] = {
    "alacritty",
    NULL
};

static const char *roficmd[] = {
    "rofi",
    "-show",
    "drun",
    NULL
};

/* key bindings */

static const Key keys[] = {

    /* terminal */
    { MODKEY, XK_Return, spawn, {.v = termcmd} },

    /* launcher */
    { MODKEY, XK_r, spawn, {.v = roficmd} },

    /* close window */
    { MODKEY, XK_q, killclient, {0} },

    /* quit dwm */
    { MODKEY|ShiftMask, XK_q, quit, {0} },

    /* focus */
    { MODKEY, XK_j, focusstack, {.i = +1} },
    { MODKEY, XK_k, focusstack, {.i = -1} },

    /* master count */
    { MODKEY, XK_i, incnmaster, {.i = +1} },
    { MODKEY, XK_d, incnmaster, {.i = -1} },

    /* master size */
    { MODKEY, XK_h, setmfact, {.f = -0.05} },
    { MODKEY, XK_l, setmfact, {.f = +0.05} },

    /* cycle layouts */
    { MODKEY, XK_space, setlayout, {0} },

    /* toggle floating */
    { MODKEY|ShiftMask, XK_space, togglefloating, {0} },

    /* toggle bar */
    { MODKEY, XK_b, togglebar, {0} },

    /* fullscreen */
    { MODKEY, XK_f,
        spawn, SHCMD("wmctrl -r :ACTIVE: -b toggle,fullscreen") },

    /* lock screen */
    { MODKEY|ShiftMask, XK_e,
        spawn, SHCMD("i3lock -c 000000") },

    /* workspaces */
    TAGKEYS(XK_1, 0)
    TAGKEYS(XK_2, 1)
    TAGKEYS(XK_3, 2)
    TAGKEYS(XK_4, 3)
    TAGKEYS(XK_5, 4)
    TAGKEYS(XK_6, 5)
    TAGKEYS(XK_7, 6)
    TAGKEYS(XK_8, 7)
    TAGKEYS(XK_9, 8)
};

/* mouse bindings */

static const Button buttons[] = {

    /* layout symbol */
    { ClkLtSymbol, 0, Button1, setlayout, {0} },
    { ClkLtSymbol, 0, Button3, setlayout, {.v = &layouts[2]} },

    /* move window */
    { ClkClientWin, MODKEY, Button1, movemouse, {0} },

    /* resize window */
    { ClkClientWin, MODKEY, Button3, resizemouse, {0} },

    /* toggle floating */
    { ClkClientWin, MODKEY, Button2, togglefloating, {0} },

    /* focus window */
    { ClkClientWin, 0, Button1, focus, {0} },
};
DWM_CONFIG

###############################################################################
# Compile / install dwm
###############################################################################

msg "Compiling dwm"

make clean
make

msg "Installing custom dwm"

make PREFIX=/usr/local install

if [[ ! -x /usr/local/bin/dwm ]]; then
    die "Custom dwm failed to install."
fi

###############################################################################
# User account
###############################################################################

msg "Creating user account"

if ! id "$USERNAME" >/dev/null 2>&1; then
    useradd \
        -m \
        -G wheel,audio,video \
        -s /bin/bash \
        "$USERNAME"
else
    usermod \
        -aG wheel,audio,video \
        "$USERNAME"
fi

###############################################################################
# Password
###############################################################################

msg "Setting user password"

if [[ ! -s "$PASSWORD_FILE" ]]; then
    die "Password file is missing."
fi

USER_PASSWORD="$(cat "$PASSWORD_FILE")"

printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | chpasswd

unset USER_PASSWORD

###############################################################################
# Root account
###############################################################################

passwd -l root

###############################################################################
# Sudo
###############################################################################

mkdir -p /etc/sudoers.d

cat > "/etc/sudoers.d/${USERNAME}" <<EOF
${USERNAME} ALL=(ALL:ALL) ALL
EOF

chmod 440 "/etc/sudoers.d/${USERNAME}"

###############################################################################
# X session
###############################################################################

msg "Configuring dwm X session"

cat > /usr/share/xsessions/dwm.desktop <<EOF
[Desktop Entry]
Name=dwm
Comment=Custom dwm
Exec=/usr/local/bin/dwm
Type=Application
DesktopNames=dwm
EOF

###############################################################################
# LightDM
###############################################################################

msg "Configuring LightDM"

mkdir -p /etc/lightdm

cat > /etc/lightdm/lightdm.conf <<EOF
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=dwm
EOF

###############################################################################
# User configuration directories
###############################################################################

msg "Creating user configuration"

install -d -o "$USERNAME" -g "$USERNAME" \
    "/home/$USERNAME/.config"

install -d -o "$USERNAME" -g "$USERNAME" \
    "/home/$USERNAME/.config/rofi"

install -d -o "$USERNAME" -g "$USERNAME" \
    "/home/$USERNAME/.config/dunst"

install -d -o "$USERNAME" -g "$USERNAME" \
    "/home/$USERNAME/.config/picom"

###############################################################################
# Rofi
###############################################################################

cat > "/home/$USERNAME/.config/rofi/config.rasi" <<'EOF'
configuration {
    show-icons: true;
    drun-display-format: "{name}";
    display-drun: "Applications";
}
EOF

chown "$USERNAME:$USERNAME" \
    "/home/$USERNAME/.config/rofi/config.rasi"

###############################################################################
# Picom
###############################################################################

cat > "/home/$USERNAME/.config/picom/picom.conf" <<'EOF'
backend = "xrender";

vsync = true;

shadow = true;
shadow-radius = 12;
shadow-offset-x = -12;
shadow-offset-y = -12;

fading = true;
fade-in-step = 0.03;
fade-out-step = 0.03;

inactive-opacity = 1.0;
frame-opacity = 1.0;

corner-radius = 0;
EOF

chown "$USERNAME:$USERNAME" \
    "/home/$USERNAME/.config/picom/picom.conf"

###############################################################################
# X startup
###############################################################################

cat > "/home/$USERNAME/.xprofile" <<'EOF'
#!/bin/sh

dunst &
picom &

# Wallpaper can be added later:
# feh --bg-fill ~/Pictures/wallpaper.jpg &

EOF

chmod 755 "/home/$USERNAME/.xprofile"

chown "$USERNAME:$USERNAME" \
    "/home/$USERNAME/.xprofile"

###############################################################################
# OpenRC services
###############################################################################

msg "Enabling OpenRC services"

rc-update add connmand default
rc-update add elogind boot
rc-update add dbus default
rc-update add lightdm default
rc-update add bluetooth default

###############################################################################
# GRUB
###############################################################################

msg "Installing GRUB"

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=Artix \
    --recheck

grub-mkconfig -o /boot/grub/grub.cfg

###############################################################################
# Initramfs
###############################################################################

msg "Generating initramfs"

mkinitcpio -P

###############################################################################
# XLibre checker
###############################################################################

cat > /usr/local/bin/check-xlibre <<'EOF'
#!/bin/bash

echo
echo "X server vendor:"
echo

if command -v xdpyinfo >/dev/null 2>&1; then
    xdpyinfo | grep -i vendor || true
else
    echo "xdpyinfo is not installed."
fi

echo
echo "XLibre packages:"
pacman -Q | grep -i xlibre || true
EOF

chmod 755 /usr/local/bin/check-xlibre

###############################################################################
# dwm checker
###############################################################################

cat > /usr/local/bin/check-dwm <<'EOF'
#!/bin/bash

echo
echo "dwm binary:"
command -v dwm || true

echo
echo "dwm version:"
dwm -v 2>&1 || true

echo
echo "X session:"
cat /usr/share/xsessions/dwm.desktop

echo
echo "Supporting packages:"
pacman -Q alacritty rofi i3lock wmctrl 2>/dev/null || true
EOF

chmod 755 /usr/local/bin/check-dwm

###############################################################################
# Cleanup
###############################################################################

msg "Cleaning temporary files"

rm -f "$PASSWORD_FILE"
rm -f /usr/local/src/dwm-"$DWM_VERSION".tar.gz

chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"

###############################################################################
# Final verification
###############################################################################

msg "Final verification"

echo
echo "Hostname : $HOSTNAME"
echo "User     : $USERNAME"
echo "Timezone : $TIMEZONE"
echo "Keyboard : $KEYMAP"
echo "Locale   : $LOCALE"
echo
echo "Desktop:"
echo "  Window manager : Custom dwm ${DWM_VERSION}"
echo "  Display server : XLibre"
echo "  Display manager: LightDM"
echo "  Init           : OpenRC"
echo "  Network        : ConnMan"
echo "  Audio          : PipeWire"
echo
echo "dwm:"
ls -l /usr/local/bin/dwm
echo
echo "X session:"
cat /usr/share/xsessions/dwm.desktop

echo
echo "Custom keybindings:"
echo "  Super + Enter           -> Alacritty"
echo "  Super + R               -> Rofi"
echo "  Super + Q               -> Close window"
echo "  Super + Shift + Q       -> Quit dwm"
echo "  Super + J / K           -> Focus next / previous"
echo "  Super + I / D           -> Increase / decrease master count"
echo "  Super + H / L           -> Shrink / grow master area"
echo "  Super + Space           -> Cycle layout"
echo "  Super + Shift + Space   -> Toggle floating"
echo "  Super + B               -> Toggle bar"
echo "  Super + F               -> Fullscreen"
echo "  Super + Shift + E       -> Lock screen"
echo "  Super + 1-9             -> Workspaces"
echo "  Super + Shift + 1-9     -> Move window to workspace"
echo "  Super + Left Mouse      -> Move window"
echo "  Super + Right Mouse     -> Resize window"

echo
echo "Verification commands after login:"
echo "  check-dwm"
echo "  check-xlibre"

echo
echo "Chroot installation complete."

CHROOT_SCRIPT

chmod 700 "$MOUNTPOINT/root/install-chroot.sh"

###############################################################################
# Run chroot
###############################################################################

msg "Running Artix chroot installer"

artix-chroot "$MOUNTPOINT" /root/install-chroot.sh

###############################################################################
# Cleanup installer files
###############################################################################

rm -f "$MOUNTPOINT/root/install-vars"
rm -f "$MOUNTPOINT/root/install-chroot.sh"
rm -f "$MOUNTPOINT/root/user-password"

sync

###############################################################################
# Unmount
###############################################################################

msg "Unmounting target"

umount -R "$MOUNTPOINT"

###############################################################################
# Finished
###############################################################################

echo
echo "============================================================"
echo "INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Installed:"
echo
echo "  Artix Linux"
echo "  OpenRC"
echo "  XLibre"
echo "  LightDM"
echo "  Custom dwm ${DWM_VERSION}"
echo "  PipeWire"
echo "  ConnMan"
echo "  Bluetooth"
echo "  Flatpak"
echo "  Alacritty"
echo "  Rofi"
echo
echo "The first dwm session includes the custom keybindings."
echo
echo "Remove the installation USB before rebooting."
echo

read -rp "Reboot now? [y/N]: " REBOOT_NOW

if [[ "$REBOOT_NOW" =~ ^[Yy]$ ]]; then
    reboot
fi
