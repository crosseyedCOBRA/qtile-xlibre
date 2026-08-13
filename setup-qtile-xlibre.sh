#!/usr/bin/env bash
# Qtile + XLibre setup for Fedora Server
# Run as your normal user (not root) — sudo is called where needed.
set -euo pipefail

echo "==> Updating system"
sudo dnf update -y

echo "==> Installing core X11 stack (xinit, drivers, dbus, mesa)"
# Note: xorg-x11-server-utils was retired in Fedora ~2021 and split into
# individual packages. xrandr/xset/xsetroot are the commonly-needed ones.
sudo dnf install -y \
  xorg-x11-xinit \
  xorg-x11-drivers \
  xrandr \
  xset \
  xsetroot \
  dbus-x11 \
  mesa-dri-drivers

echo "==> Enabling XLibre Copr repo"
sudo dnf copr enable -y @xlibre/xlibre-xserver

echo "==> Installing XLibre X server + libinput driver"
sudo dnf install -y --allowerasing \
  xlibre-xserver \
  xlibre-xf86-input-libinput

echo "==> Installing Qtile + a terminal emulator"
sudo dnf install -y qtile alacritty

echo "==> Writing ~/.xinitrc"
cat > "$HOME/.xinitrc" <<'EOF'
exec qtile start
EOF
chmod +x "$HOME/.xinitrc"

echo "==> Installing LightDM"
sudo dnf install -y lightdm lightdm-gtk-greeter

echo "==> Setting Qtile as the default LightDM session"
sudo mkdir -p /etc/lightdm/lightdm.conf.d
sudo tee /etc/lightdm/lightdm.conf.d/50-qtile.conf > /dev/null <<'EOF'
[Seat:*]
user-session=qtile
EOF

echo "==> Setting graphical target as default boot target"
sudo systemctl set-default graphical.target

echo "==> Enabling and starting LightDM"
sudo systemctl enable lightdm --now

echo "==> Done."
echo "LightDM is running and will start automatically on boot, with Qtile"
echo "pre-selected as the session. Reboot to land straight on the login screen:"
echo "  sudo reboot"
