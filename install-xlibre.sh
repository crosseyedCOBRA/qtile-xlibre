#!/bin/bash
# install-xlibre.sh -- same as install.sh, but installs XLibre instead of
# standard xorg-x11-server as the actual X server.
#
# CRITICAL: only run this on a system that has NEVER had the 'x11' pattern
# or xorg-x11-server installed. This is what lets x11-xlibre install cleanly
# with no file conflicts, instead of needing the "ignore dependencies"
# override that's required when installing it alongside an existing Xorg.
#
# Recommended: run this on a fresh, minimal openSUSE Tumbleweed VM install
# (Minimal Server Selection / text-mode install, no desktop pattern chosen).
# Do NOT run this on a machine that already has a working X11 desktop --
# that's what install.sh (the standard-Xorg version) is for.
#
# Usage:
#   1. Place this script in the same directory as the accompanying config/
#      folder and the other loose files it references (gamemode.ini,
#      Xresources, sysctl/99-gaming.conf).
#   2. Run as your normal user (NOT root) -- it calls sudo itself where needed:
#        chmod +x install-xlibre.sh
#        ./install-xlibre.sh
#
# This assumes openSUSE Tumbleweed. If you're on Leap, several repo URLs
# below (X11:windowmanagers, X11:Wayland, Packman) need the Leap variant
# swapped in -- see the comments at each repo addition.
#
# Safe to re-run: package installs are idempotent, and config files are
# copied (overwriting) rather than appended, so re-running after an update
# to this repo just re-syncs everything.

set -e  # stop on first real error, rather than plowing ahead into a broken state

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(eval echo "~$TARGET_USER")

echo "==> Installing for user: $TARGET_USER (home: $TARGET_HOME)"
echo "==> Reading config files from: $SCRIPT_DIR"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. XLibre (instead of standard xorg-x11-server) + required X11 client tools
# ---------------------------------------------------------------------------
echo "==> [1/9] Adding XLibre repo"
git clone https://github.com/xlibre-opensuse/repo.git /tmp/xlibre-repo-files
sudo cp /tmp/xlibre-repo-files/*.repo /etc/zypp/repos.d/
sudo zypper --gpg-auto-import-keys refresh

echo "==> [1/9] Installing XLibre server"
# NOTE: deliberately NOT installing the 'x11' pattern here -- that pulls in
# standard xorg-x11-server, which is exactly what would conflict with
# x11-xlibre. This only works cleanly on a system that never had the
# standard X server installed in the first place.
sudo zypper --non-interactive install x11-xlibre
sudo zypper --non-interactive install x11-xlibre-meta

echo "==> [1/9] Installing X11 client-side tools (normally bundled in the"
echo "    'x11' pattern, but we skipped that pattern to avoid pulling in"
echo "    standard xorg-x11-server). If any of these aren't found, run"
echo "    'zypper search <name>' to find the real package name on your system:"
sudo zypper --non-interactive install \
    xrdb \
    xset \
    xsetroot \
    xrandr \
    xinit \
    xterm \
    xf86-input-libinput \
    xf86-video-amdgpu

echo "==> [1/9] Adding qtile repo (X11:windowmanagers) and installing qtile"
sudo zypper --non-interactive addrepo \
    https://download.opensuse.org/repositories/X11:windowmanagers/openSUSE_Tumbleweed/X11:windowmanagers.repo || true
sudo zypper --gpg-auto-import-keys refresh
sudo zypper --non-interactive install qtile

# ---------------------------------------------------------------------------
# 2. Core desktop tools
# ---------------------------------------------------------------------------
echo "==> [2/9] Installing core desktop tools"
sudo zypper --non-interactive install \
    kitty \
    rofi \
    picom \
    xwallpaper \
    autorandr \
    thunar \
    pavucontrol \
    fastfetch \
    alacritty \
    maim slop xclip \
    lightdm lightdm-gtk-greeter \
    python3-pip python3-pipx gcc

# ---------------------------------------------------------------------------
# 3. Fonts
# ---------------------------------------------------------------------------
echo "==> [3/9] Installing fonts"
sudo zypper --non-interactive install symbols-only-nerd-fonts jetbrains-mono-fonts

mkdir -p "$TARGET_HOME/.local/share/fonts"
if [ ! -d "$TARGET_HOME/.local/share/fonts/JetBrainsMonoNerdFont" ]; then
    echo "==> Downloading JetBrainsMono Nerd Font (full glyph set) from upstream GitHub release"
    curl -sL -o /tmp/JetBrainsMono.zip \
        https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
    unzip -q /tmp/JetBrainsMono.zip -d "$TARGET_HOME/.local/share/fonts/JetBrainsMonoNerdFont"
    rm /tmp/JetBrainsMono.zip
else
    echo "==> JetBrainsMono Nerd Font already present, skipping download"
fi
fc-cache -f

# ---------------------------------------------------------------------------
# 4. Codecs (Packman)
# ---------------------------------------------------------------------------
echo "==> [4/9] Setting up Packman + codecs"
sudo zypper --non-interactive install opi
opi codecs || echo "!! opi codecs needs interactive confirmation -- run 'opi codecs' manually if this was skipped"
sudo zypper --non-interactive install libva-utils

# ---------------------------------------------------------------------------
# 5. Gaming stack
# ---------------------------------------------------------------------------
echo "==> [5/9] Installing gaming performance tools"
sudo zypper --non-interactive install gamemode gamemode-32bit mangohud mangohud-32bit corectrl

# CoreCtrl polkit rule + group (see earlier setup for full context)
sudo groupadd -f corectrl
sudo gpasswd -a "$TARGET_USER" corectrl
sudo tee /etc/polkit-1/rules.d/90-corectrl.rules > /dev/null << 'EOF'
polkit.addRule(function(action, subject) {
    if ((action.id == "org.corectrl.helper.init" ||
         action.id == "org.corectrl.helperkiller.init") &&
        subject.isInGroup("corectrl")) {
        return polkit.Result.YES;
    }
});
EOF

# sched_ext (scx) -- optional, only if available on your system/kernel
if sudo zypper search scx > /dev/null 2>&1; then
    sudo zypper --non-interactive install scx || echo "!! scx package not available, skipping (check kernel version >= 6.12)"
fi

# ---------------------------------------------------------------------------
# 6. LightDM as display manager
# ---------------------------------------------------------------------------
echo "==> [6/9] Enabling LightDM"
sudo systemctl enable lightdm.service

sudo tee /usr/share/xsessions/qtile.desktop > /dev/null << 'EOF'
[Desktop Entry]
Name=Qtile
Comment=Qtile Session
Exec=qtile start
Type=Application
EOF

# ---------------------------------------------------------------------------
# 7. Copy all config files into place
# ---------------------------------------------------------------------------
echo "==> [7/9] Installing config files"
mkdir -p "$TARGET_HOME/.config/qtile/icons"
mkdir -p "$TARGET_HOME/.config/rofi"
mkdir -p "$TARGET_HOME/.config/picom"
mkdir -p "$TARGET_HOME/.config/alacritty"
mkdir -p "$TARGET_HOME/.config/fastfetch"
mkdir -p "$TARGET_HOME/.config/MangoHud"
mkdir -p "$TARGET_HOME/Pictures/Screenshots"

cp "$SCRIPT_DIR/config/qtile/config.py"        "$TARGET_HOME/.config/qtile/config.py"
cp "$SCRIPT_DIR/config/qtile/autostart.sh"     "$TARGET_HOME/.config/qtile/autostart.sh"
cp "$SCRIPT_DIR/config/qtile/powermenu.sh"     "$TARGET_HOME/.config/qtile/powermenu.sh"
cp "$SCRIPT_DIR/config/qtile/toggle-picom.sh"  "$TARGET_HOME/.config/qtile/toggle-picom.sh"
cp "$SCRIPT_DIR/config/qtile/screenshot.sh"    "$TARGET_HOME/.config/qtile/screenshot.sh"
cp "$SCRIPT_DIR/config/qtile/icons/opensuse-logo.png" "$TARGET_HOME/.config/qtile/icons/opensuse-logo.png"
cp "$SCRIPT_DIR/config/rofi/theme.rasi"        "$TARGET_HOME/.config/rofi/theme.rasi"
cp "$SCRIPT_DIR/config/picom/picom.conf"       "$TARGET_HOME/.config/picom/picom.conf"
cp "$SCRIPT_DIR/config/alacritty/alacritty.toml" "$TARGET_HOME/.config/alacritty/alacritty.toml"
cp "$SCRIPT_DIR/config/fastfetch/config.jsonc" "$TARGET_HOME/.config/fastfetch/config.jsonc"
cp "$SCRIPT_DIR/config/MangoHud/MangoHud.conf" "$TARGET_HOME/.config/MangoHud/MangoHud.conf"
cp "$SCRIPT_DIR/gamemode.ini"                  "$TARGET_HOME/.config/gamemode.ini"
cp "$SCRIPT_DIR/Xresources"                    "$TARGET_HOME/.Xresources"

chmod +x "$TARGET_HOME/.config/qtile/autostart.sh"
chmod +x "$TARGET_HOME/.config/qtile/powermenu.sh"
chmod +x "$TARGET_HOME/.config/qtile/toggle-picom.sh"
chmod +x "$TARGET_HOME/.config/qtile/screenshot.sh"

chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config" "$TARGET_HOME/.Xresources" "$TARGET_HOME/Pictures"

# ---------------------------------------------------------------------------
# 8. System-level sysctl tweaks
# ---------------------------------------------------------------------------
echo "==> [8/9] Applying sysctl gaming tweaks"
sudo cp "$SCRIPT_DIR/sysctl/99-gaming.conf" /etc/sysctl.d/99-gaming.conf
sudo sysctl --system

# ---------------------------------------------------------------------------
# 9. Done
# ---------------------------------------------------------------------------
echo "==> [9/9] Done"
echo ""
echo "IMPORTANT -- things this script CANNOT do for you, do these manually:"
echo "  - Set up your actual xrandr monitor layout and 'autorandr --save <profile>'"
echo "    (this is hardware-specific -- see the commented-out block at the top"
echo "    of ~/.config/qtile/autostart.sh)"
echo "  - Set your wallpaper image at ~/Pictures/wallpaper.jpg (referenced by autostart.sh)"
echo "  - Set the amdgpu.ppfeaturemask and amd_pstate=active GRUB kernel params"
echo "    manually in /etc/default/grub, then: sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
echo "  - Verify sensor tag names (Tctl / edge) match your actual hardware:"
echo "    python3 -c \"import psutil, pprint; pprint.pprint(psutil.sensors_temperatures())\""
echo ""
echo "Reboot now, then log into the 'Qtile' session from the LightDM greeter."
