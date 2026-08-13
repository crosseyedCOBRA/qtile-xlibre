#!/usr/bin/env bash
# Qtile + XLibre setup for Fedora Server
# Run as your normal user (not root) — sudo is called where needed.
set -euo pipefail

echo "==> Updating system"
sudo dnf update -y

echo "==> Installing core X11 stack (xinit, drivers, dbus, mesa)"
sudo dnf install -y \
  xorg-x11-server-utils \
  xorg-x11-xinit \
  xorg-x11-drivers \
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

echo "==> Setting up Qtile config"
mkdir -p "$HOME/.config/qtile"
if [ ! -f "$HOME/.config/qtile/config.py" ]; then
  cp /usr/share/doc/qtile/default_config.py "$HOME/.config/qtile/config.py"
fi

echo "==> Writing ~/.xinitrc"
cat > "$HOME/.xinitrc" <<'EOF'
exec qtile start
EOF
chmod +x "$HOME/.xinitrc"

echo "==> Done."
echo "Log in at the console and run 'startx' to launch Qtile on XLibre."
echo ""
echo "Optional: for a graphical login manager instead of startx, run:"
echo "  sudo dnf install -y lightdm lightdm-gtk-greeter"
echo "  sudo systemctl enable lightdm --now"
