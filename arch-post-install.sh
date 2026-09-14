#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  Arch Linux Post-Install: XLibre + Qtile + Full Desktop        ║
# ║  Run as:  sudo ./arch-post-install.sh                          ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Sanity ───────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root → sudo ./arch-post-install.sh"
    exit 1
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
REAL_HOME=$(eval echo "~$REAL_USER")

echo "═══════════════════════════════════════════════════════════"
echo "  Arch Linux Post-Install"
echo "  User: $REAL_USER | Home: $REAL_HOME"
echo "═══════════════════════════════════════════════════════════"

step() {
    echo ""
    echo "── $1 ──────────────────────────────────────────────────"
}

# =====================================================================
# 1. FULL SYSTEM UPDATE
# =====================================================================
step "System update"
pacman -Syu --noconfirm

# =====================================================================
# 2. XLIBRE REPOSITORY
# =====================================================================
step "Adding XLibre binary repo"

# Import the signing key
curl -fsSL -o /tmp/xlibre-archlinux.asc https://xlibre-arch.github.io/xlibre-archlinux.asc
pacman-key --add /tmp/xlibre-archlinux.asc
pacman-key --finger B97F7C613F359424
pacman-key --lsign-key B97F7C613F359424
rm -f /tmp/xlibre-archlinux.asc

# Add the repo to pacman.conf (if not already there)
if ! grep -q "\[xlibre-stable\]" /etc/pacman.conf; then
    cat >> /etc/pacman.conf << 'REPO'

[xlibre-stable]
Server = https://packages.xlibre.net/arch/stable/$arch
REPO
    echo "  → xlibre-stable repo added to pacman.conf"
else
    echo "  → xlibre-stable repo already in pacman.conf"
fi

pacman -Syy

# =====================================================================
# 3. INSTALL XLIBRE
# =====================================================================
step "Installing XLibre (replaces Xorg)"

pacman -S --noconfirm xlibre-meta

# =====================================================================
# 4. GPU DRIVER
# =====================================================================
step "Detecting GPU"

GPU_INFO=$(lspci 2>/dev/null | grep -iE "vga|3d|display" || true)

if echo "$GPU_INFO" | grep -qi "nvidia"; then
    echo "  → NVIDIA detected"
    echo "  → XLibre supports nouveau out of the box."
    echo "  → For proprietary: pacman -S nvidia nvidia-utils"
    echo "  → (Not auto-installing proprietary — it can break things)"

elif echo "$GPU_INFO" | grep -qi "amd\|radeon"; then
    echo "  → AMD/Radeon detected"
    pacman -S --noconfirm --needed mesa vulkan-radeon libva-mesa-driver

elif echo "$GPU_INFO" | grep -qi "intel"; then
    echo "  → Intel detected"
    pacman -S --noconfirm --needed mesa vulkan-intel intel-media-driver

elif echo "$GPU_INFO" | grep -qi "vmware\|virtualbox\|qxl\|virtio"; then
    echo "  → Virtual machine detected"
    pacman -S --noconfirm --needed mesa
else
    echo "  → Could not detect GPU. Installing mesa as fallback."
    pacman -S --noconfirm --needed mesa
fi

# =====================================================================
# 5. QTILE + DISPLAY MANAGER
# =====================================================================
step "Installing Qtile + LightDM"

pacman -S --noconfirm --needed \
    qtile python-psutil python-iwlib \
    lightdm lightdm-gtk-greeter

systemctl enable lightdm

# =====================================================================
# 6. AUDIO — PIPEWIRE
# =====================================================================
step "Installing PipeWire audio stack"

pacman -S --noconfirm --needed \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack \
    wireplumber \
    pavucontrol

# =====================================================================
# 7. DESKTOP ESSENTIALS
# =====================================================================
step "Installing desktop packages"

pacman -S --noconfirm --needed \
    alacritty \
    rofi \
    picom \
    dunst \
    feh \
    flameshot \
    thunar gvfs thunar-volman \
    network-manager-applet \
    bluez bluez-utils \
    blueman \
    brightnessctl \
    arandr \
    lxappearance \
    polkit-gnome \
    xdg-user-dirs \
    xdg-utils \
    xclip \
    xdotool \
    xorg-xsetroot \
    xorg-xset \
    xorg-xdpyinfo

# =====================================================================
# 8. CLI TOOLS
# =====================================================================
step "Installing CLI tools"

pacman -S --noconfirm --needed \
    git \
    curl \
    wget \
    htop \
    btop \
    neovim \
    ripgrep \
    fd \
    eza \
    bat \
    tree \
    unzip \
    p7zip \
    fastfetch \
    bash-completion \
    man-db \
    man-pages

# =====================================================================
# 9. FONTS
# =====================================================================
step "Installing fonts"

pacman -S --noconfirm --needed \
    ttf-jetbrains-mono-nerd \
    noto-fonts \
    noto-fonts-cjk \
    noto-fonts-emoji \
    ttf-font-awesome \
    ttf-dejavu

# =====================================================================
# 10. BROWSER
# =====================================================================
step "Installing Firefox"
pacman -S --noconfirm --needed firefox

# =====================================================================
# 11. BUILD TOOLS (for ZarisWM later)
# =====================================================================
step "Installing build tools (C/C++, cmake, xcb — ready for ZarisWM)"

pacman -S --noconfirm --needed \
    cmake \
    pkgconf \
    xcb-util \
    xcb-util-wm \
    xcb-util-keysyms \
    xcb-util-cursor \
    xcb-util-xrm \
    libxcb \
    libx11 \
    libxft \
    libxinerama \
    libxrandr \
    pango \
    cairo \
    startup-notification

# =====================================================================
# 12. THEMING
# =====================================================================
step "Installing GTK themes + icons"

pacman -S --noconfirm --needed \
    papirus-icon-theme \
    arc-gtk-theme

# =====================================================================
# 13. INSTALL yay (AUR HELPER)
# =====================================================================
step "Installing yay (AUR helper)"

if ! command -v yay &>/dev/null; then
    cd /tmp
    sudo -u "$REAL_USER" git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    sudo -u "$REAL_USER" makepkg -si --noconfirm
    cd /
    rm -rf /tmp/yay-bin
    echo "  → yay installed"
else
    echo "  → yay already installed"
fi

# =====================================================================
# 14. ENABLE SERVICES
# =====================================================================
step "Enabling services"

systemctl enable NetworkManager
systemctl enable bluetooth

echo "  → Enabled: NetworkManager, bluetooth, lightdm"

# =====================================================================
# 15. PIPEWIRE USER AUTOSTART
# =====================================================================
step "PipeWire user autostart (handled by wireplumber)"

# PipeWire on Arch auto-starts via XDG autostart + systemd user units.
# Just ensure the user units are enabled:
su - "$REAL_USER" -c "systemctl --user enable pipewire.socket 2>/dev/null" || true
su - "$REAL_USER" -c "systemctl --user enable pipewire-pulse.socket 2>/dev/null" || true
su - "$REAL_USER" -c "systemctl --user enable wireplumber 2>/dev/null" || true

echo "  → PipeWire user services enabled"

# =====================================================================
# 16. XDG USER DIRS
# =====================================================================
step "Creating XDG user directories"
su - "$REAL_USER" -c "xdg-user-dirs-update" 2>/dev/null || true

# =====================================================================
# 17. QTILE CONFIG
# =====================================================================
step "Writing Qtile config"

QTILE_DIR="$REAL_HOME/.config/qtile"
mkdir -p "$QTILE_DIR"

# ── config.py ────────────────────────────────────────────────────────
cat > "$QTILE_DIR/config.py" << 'PYEOF'
import os
import subprocess
from libqtile import bar, layout, widget, hook
from libqtile.config import Click, Drag, Group, Key, Match, Screen
from libqtile.lazy import lazy

mod = "mod4"
terminal = "alacritty"
launcher = "rofi -show drun -show-icons"
browser = "firefox"
file_manager = "thunar"

# ── Catppuccin Mocha ─────────────────────────────────────────────────
c = {
    "bg":     "#1e1e2e", "bg_alt": "#313244",
    "fg":     "#cdd6f4", "fg_dim": "#6c7086",
    "blue":   "#89b4fa", "green":  "#a6e3a1",
    "red":    "#f38ba8", "peach":  "#fab387",
    "mauve":  "#cba6f7", "teal":   "#94e2d5",
    "yellow": "#f9e2af",
}

# ── Keys ─────────────────────────────────────────────────────────────
keys = [
    Key([mod], "h", lazy.layout.left()),
    Key([mod], "l", lazy.layout.right()),
    Key([mod], "j", lazy.layout.down()),
    Key([mod], "k", lazy.layout.up()),
    Key([mod], "space", lazy.layout.next()),

    Key([mod, "shift"], "h", lazy.layout.shuffle_left()),
    Key([mod, "shift"], "l", lazy.layout.shuffle_right()),
    Key([mod, "shift"], "j", lazy.layout.shuffle_down()),
    Key([mod, "shift"], "k", lazy.layout.shuffle_up()),

    Key([mod, "control"], "h", lazy.layout.grow_left()),
    Key([mod, "control"], "l", lazy.layout.grow_right()),
    Key([mod, "control"], "j", lazy.layout.grow_down()),
    Key([mod, "control"], "k", lazy.layout.grow_up()),
    Key([mod], "n", lazy.layout.normalize()),

    Key([mod], "Tab", lazy.next_layout()),
    Key([mod], "f", lazy.window.toggle_fullscreen()),
    Key([mod, "shift"], "f", lazy.window.toggle_floating()),

    Key([mod], "Return", lazy.spawn(terminal)),
    Key([mod], "r",      lazy.spawn(launcher)),
    Key([mod], "b",      lazy.spawn(browser)),
    Key([mod], "e",      lazy.spawn(file_manager)),
    Key([], "Print",     lazy.spawn("flameshot gui")),

    Key([mod], "q",          lazy.window.kill()),
    Key([mod, "shift"], "r", lazy.reload_config()),
    Key([mod, "shift"], "q", lazy.shutdown()),

    Key([], "XF86AudioRaiseVolume",  lazy.spawn("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+")),
    Key([], "XF86AudioLowerVolume",  lazy.spawn("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")),
    Key([], "XF86AudioMute",         lazy.spawn("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")),
    Key([], "XF86MonBrightnessUp",   lazy.spawn("brightnessctl set +5%")),
    Key([], "XF86MonBrightnessDown", lazy.spawn("brightnessctl set 5%-")),
]

# ── Groups ───────────────────────────────────────────────────────────
groups = [Group(i) for i in "123456789"]
for g in groups:
    keys.extend([
        Key([mod], g.name, lazy.group[g.name].toscreen()),
        Key([mod, "shift"], g.name, lazy.window.togroup(g.name, switch_group=True)),
    ])

# ── Layouts ──────────────────────────────────────────────────────────
lt = {"border_width": 2, "margin": 6, "border_focus": c["blue"], "border_normal": c["bg_alt"]}
layouts = [
    layout.Columns(**lt, border_on_single=True),
    layout.MonadTall(**lt),
    layout.Max(**lt),
]

# ── Bar ──────────────────────────────────────────────────────────────
widget_defaults = dict(font="JetBrainsMono Nerd Font", fontsize=13, padding=8,
                       foreground=c["fg"], background=c["bg"])
extension_defaults = widget_defaults.copy()

screens = [
    Screen(top=bar.Bar([
        widget.Spacer(length=8),
        widget.GroupBox(
            active=c["fg"], inactive=c["fg_dim"], highlight_method="line",
            highlight_color=[c["bg"], c["bg_alt"]], this_current_screen_border=c["blue"],
            urgent_border=c["red"], rounded=False, disable_drag=True, fontsize=15, padding_x=6,
        ),
        widget.Sep(linewidth=1, padding=12, foreground=c["fg_dim"]),
        widget.CurrentLayout(foreground=c["mauve"]),
        widget.Spacer(),
        widget.WindowName(foreground=c["fg_dim"], max_chars=60),
        widget.Spacer(),
        widget.Systray(padding=6),
        widget.Sep(linewidth=1, padding=12, foreground=c["fg_dim"]),
        widget.CPU(format="  {load_percent}%", foreground=c["teal"], update_interval=3),
        widget.Memory(format="  {MemUsed:.1f}{mm}", foreground=c["green"], measure_mem="G", update_interval=3),
        widget.Volume(fmt="  {}", foreground=c["peach"]),
        widget.Clock(format="  %a %d %b  %H:%M", foreground=c["blue"]),
        widget.Spacer(length=8),
    ], size=30, background=c["bg"], margin=[4, 8, 0, 8], opacity=0.95)),
]

# ── Mouse ────────────────────────────────────────────────────────────
mouse = [
    Drag([mod], "Button1", lazy.window.set_position_floating(), start=lazy.window.get_position()),
    Drag([mod], "Button3", lazy.window.set_size_floating(), start=lazy.window.get_size()),
    Click([mod], "Button2", lazy.window.bring_to_front()),
]

# ── Floating ─────────────────────────────────────────────────────────
floating_layout = layout.Floating(
    float_rules=[*layout.Floating.default_float_rules,
        Match(wm_class="pavucontrol"), Match(wm_class="arandr"),
        Match(wm_class="blueman-manager"), Match(wm_class="flameshot"),
        Match(title="pinentry"),
    ],
    border_focus=c["mauve"], border_normal=c["bg_alt"], border_width=2,
)

# ── Autostart ────────────────────────────────────────────────────────
@hook.subscribe.startup_once
def autostart():
    script = os.path.expanduser("~/.config/qtile/autostart.sh")
    if os.path.isfile(script):
        subprocess.Popen([script])

dgroups_key_binder = None
dgroups_app_rules = []
follow_mouse_focus = True
bring_front_click = False
floats_kept_above = True
cursor_warp = False
auto_fullscreen = True
focus_on_window_activation = "smart"
reconfigure_screens = True
auto_minimize = True
wl_input_rules = None
wmname = "Qtile"
PYEOF

# ── autostart.sh ─────────────────────────────────────────────────────
cat > "$QTILE_DIR/autostart.sh" << 'SHEOF'
#!/usr/bin/env bash

# Compositor
picom --daemon --backend glx --vsync &

# Wallpaper
if [ -f ~/wallpaper.jpg ]; then
    feh --bg-fill ~/wallpaper.jpg &
elif [ -f ~/wallpaper.png ]; then
    feh --bg-fill ~/wallpaper.png &
else
    xsetroot -solid "#1e1e2e" &
fi

# Notifications
dunst &

# Network tray
nm-applet &

# Polkit
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# Cursor
xsetroot -cursor_name left_ptr &
SHEOF
chmod +x "$QTILE_DIR/autostart.sh"

# ── .xinitrc fallback ────────────────────────────────────────────────
cat > "$REAL_HOME/.xinitrc" << 'XIEOF'
#!/bin/sh
[ -d /etc/X11/xinit/xinitrc.d ] && for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
    [ -x "$f" ] && . "$f"
done
exec qtile start
XIEOF
chmod +x "$REAL_HOME/.xinitrc"

chown -R "$REAL_USER:$REAL_USER" "$QTILE_DIR"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.xinitrc"

# =====================================================================
# 18. ALACRITTY CONFIG
# =====================================================================
step "Writing Alacritty config"

ALACRITTY_DIR="$REAL_HOME/.config/alacritty"
mkdir -p "$ALACRITTY_DIR"

cat > "$ALACRITTY_DIR/alacritty.toml" << 'ALEOF'
[font]
size = 11.0

[font.normal]
family = "JetBrainsMono Nerd Font"
style = "Regular"

[font.bold]
family = "JetBrainsMono Nerd Font"
style = "Bold"

[font.italic]
family = "JetBrainsMono Nerd Font"
style = "Italic"

[window]
padding = { x = 8, y = 8 }
opacity = 0.95

[colors.primary]
background = "#1E1E2E"
foreground = "#CDD6F4"

[colors.cursor]
text = "#1E1E2E"
cursor = "#F5E0DC"

[colors.normal]
black   = "#45475A"
red     = "#F38BA8"
green   = "#A6E3A1"
yellow  = "#F9E2AF"
blue    = "#89B4FA"
magenta = "#F5C2E7"
cyan    = "#94E2D5"
white   = "#BAC2DE"

[colors.bright]
black   = "#585B70"
red     = "#F38BA8"
green   = "#A6E3A1"
yellow  = "#F9E2AF"
blue    = "#89B4FA"
magenta = "#F5C2E7"
cyan    = "#94E2D5"
white   = "#A6ADC8"
ALEOF

chown -R "$REAL_USER:$REAL_USER" "$ALACRITTY_DIR"

# =====================================================================
# 19. PICOM CONFIG
# =====================================================================
step "Writing Picom config"

PICOM_DIR="$REAL_HOME/.config/picom"
mkdir -p "$PICOM_DIR"

cat > "$PICOM_DIR/picom.conf" << 'PCEOF'
backend = "glx";
vsync = true;

active-opacity = 1.0;
inactive-opacity = 0.92;
frame-opacity = 1.0;
inactive-opacity-override = false;

fading = true;
fade-in-step = 0.03;
fade-out-step = 0.03;
fade-delta = 5;

shadow = true;
shadow-radius = 12;
shadow-offset-x = -7;
shadow-offset-y = -7;
shadow-opacity = 0.5;
shadow-exclude = [
    "name = 'Notification'",
    "class_g ?= 'Dunst'",
    "_GTK_FRAME_EXTENTS@:c",
];

corner-radius = 8;
rounded-corners-exclude = [
    "window_type = 'dock'",
    "window_type = 'desktop'",
];
PCEOF

chown -R "$REAL_USER:$REAL_USER" "$PICOM_DIR"

# =====================================================================
# 20. DUNST CONFIG
# =====================================================================
step "Writing Dunst config"

DUNST_DIR="$REAL_HOME/.config/dunst"
mkdir -p "$DUNST_DIR"

cat > "$DUNST_DIR/dunstrc" << 'DNEOF'
[global]
    monitor = 0
    follow = mouse
    width = 350
    height = 150
    origin = top-right
    offset = 12x12
    progress_bar = true
    indicate_hidden = yes
    transparency = 10
    separator_height = 2
    padding = 12
    horizontal_padding = 12
    frame_width = 2
    frame_color = "#89b4fa"
    separator_color = frame
    sort = yes
    font = JetBrainsMono Nerd Font 10
    markup = full
    format = "<b>%s</b>\n%b"
    alignment = left
    show_age_threshold = 60
    icon_position = left
    max_icon_size = 48
    corner_radius = 8

[urgency_low]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    timeout = 5

[urgency_normal]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    timeout = 10

[urgency_critical]
    background = "#1e1e2e"
    foreground = "#f38ba8"
    frame_color = "#f38ba8"
    timeout = 0
DNEOF

chown -R "$REAL_USER:$REAL_USER" "$DUNST_DIR"

# =====================================================================
# 21. ROFI CONFIG
# =====================================================================
step "Writing Rofi config"

ROFI_DIR="$REAL_HOME/.config/rofi"
mkdir -p "$ROFI_DIR"

cat > "$ROFI_DIR/config.rasi" << 'ROEOF'
configuration {
    show-icons: true;
    icon-theme: "Papirus-Dark";
    display-drun: " Apps";
    display-run: " Run";
    display-window: " Windows";
    font: "JetBrainsMono Nerd Font 12";
}

* {
    bg:     #1e1e2edd;
    bg-alt: #313244;
    fg:     #cdd6f4;
    accent: #89b4fa;
    urgent: #f38ba8;

    background-color: transparent;
    text-color: @fg;
}

window {
    width: 500px;
    background-color: @bg;
    border: 2px;
    border-color: @accent;
    border-radius: 12px;
    padding: 20px;
}

inputbar {
    children: [prompt, entry];
    spacing: 8px;
    padding: 8px 12px;
    background-color: @bg-alt;
    border-radius: 8px;
}

prompt {
    text-color: @accent;
}

entry {
    placeholder: "Search...";
}

listview {
    lines: 8;
    columns: 1;
    spacing: 4px;
    padding: 8px 0 0 0;
}

element {
    padding: 8px 12px;
    border-radius: 6px;
}

element selected {
    background-color: @accent;
    text-color: #1e1e2e;
}
ROEOF

chown -R "$REAL_USER:$REAL_USER" "$ROFI_DIR"

# =====================================================================
# DONE
# =====================================================================
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✓ SETUP COMPLETE"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Installed:"
echo "    • XLibre X server (xlibre-meta from xlibre-stable repo)"
echo "    • Qtile + full config (Catppuccin Mocha)"
echo "    • LightDM display manager"
echo "    • PipeWire audio"
echo "    • Bluetooth (bluez + blueman)"
echo "    • NetworkManager"
echo "    • Alacritty, Rofi, Picom, Dunst, Feh, Flameshot"
echo "    • JetBrainsMono Nerd Font + Noto fonts"
echo "    • Firefox, yay (AUR helper)"
echo "    • Build tools ready for ZarisWM"
echo ""
echo "  Verify XLibre after reboot:"
echo "    xdpyinfo | grep vendor"
echo ""
echo "  Build ZarisWM when ready:"
echo "    git clone https://github.com/crosseyedCOBRA/zaris.git"
echo "    cd zaris && mkdir build && cd build"
echo "    cmake -DCMAKE_BUILD_TYPE=Release .."
echo "    make -j\$(nproc) && sudo make install"
echo ""
echo "  → sudo reboot"
echo ""
