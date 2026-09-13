#!/usr/bin/env bash

set -Eeuo pipefail

CONFIG_DIR="/etc/nixos"
CONFIG_FILE="${CONFIG_DIR}/configuration.nix"
DWM_DIR="${CONFIG_DIR}/dwm"
BACKUP_FILE="${CONFIG_DIR}/configuration.nix.backup.$(date +%Y%m%d-%H%M%S)"

cleanup_on_error() {
    echo
    echo "============================================================"
    echo "ERROR: NixOS dwm bootstrap failed."
    echo "============================================================"
    echo
    echo "Your original configuration was backed up to:"
    echo "  ${BACKUP_FILE}"
    echo
    echo "No reboot has been performed."
    echo
}

trap cleanup_on_error ERR

echo "============================================================"
echo " NixOS + X11 + LightDM + Custom dwm Bootstrap"
echo "============================================================"
echo

if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run this script with sudo:"
    echo
    echo "  sudo bash $0"
    echo
    exit 1
fi

if [[ ! -f /etc/NIXOS ]]; then
    echo "ERROR: This does not appear to be a NixOS installation."
    exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: ${CONFIG_FILE} does not exist."
    echo "Run the normal NixOS installer first."
    exit 1
fi

if [[ ! -f "${CONFIG_DIR}/hardware-configuration.nix" ]]; then
    echo "ERROR: hardware-configuration.nix was not found."
    echo "Run nixos-generate-config / the normal NixOS installer first."
    exit 1
fi

# ------------------------------------------------------------
# Determine the existing normal user.
# ------------------------------------------------------------

TARGET_USER="${SUDO_USER:-}"

if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
    TARGET_USER="$(
        awk -F: '
            $3 >= 1000 && $3 < 60000 && $1 != "nobody" {
                print $1
                exit
            }
        ' /etc/passwd
    )"
fi

if [[ -z "${TARGET_USER}" ]]; then
    echo "Could not automatically determine your normal user."
    read -r -p "Enter your NixOS username: " TARGET_USER
fi

if ! id "${TARGET_USER}" >/dev/null 2>&1; then
    echo "ERROR: User '${TARGET_USER}' does not exist."
    exit 1
fi

TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

if [[ -z "${TARGET_HOME}" || ! -d "${TARGET_HOME}" ]]; then
    echo "ERROR: Could not determine home directory for ${TARGET_USER}."
    exit 1
fi

echo "Using NixOS user: ${TARGET_USER}"
echo "Home directory:   ${TARGET_HOME}"
echo

# ------------------------------------------------------------
# Determine the existing stateVersion if possible.
# ------------------------------------------------------------

STATE_VERSION="$(
    grep -oE 'system\.stateVersion[[:space:]]*=[[:space:]]*"[^"]+"' \
        "${CONFIG_FILE}" 2>/dev/null \
        | head -n1 \
        | grep -oE '"[0-9]{2}\.[0-9]{2}"' \
        | tr -d '"' \
        || true
)"

if [[ -z "${STATE_VERSION}" ]]; then
    STATE_VERSION="26.05"
fi

echo "Using system.stateVersion: ${STATE_VERSION}"
echo

# ------------------------------------------------------------
# Backup existing configuration.
# ------------------------------------------------------------

echo "Backing up existing configuration..."
cp -a "${CONFIG_FILE}" "${BACKUP_FILE}"

echo "Backup created:"
echo "  ${BACKUP_FILE}"
echo

# ------------------------------------------------------------
# Create dwm configuration directory.
# ------------------------------------------------------------

mkdir -p "${DWM_DIR}"

# ------------------------------------------------------------
# Write custom dwm config.
#
# These bindings are compiled directly into dwm.
# ------------------------------------------------------------

cat > "${DWM_DIR}/config.def.h" <<'EOF_DWM'
/* Custom dwm configuration for NixOS */

static const unsigned int borderpx  = 1;
static const unsigned int snap      = 32;
static const int showbar            = 1;
static const int topbar             = 1;

static const char *fonts[] = {
	"JetBrains Mono:size=10"
};

static const char col_gray1[]       = "#222222";
static const char col_gray2[]       = "#444444";
static const char col_gray3[]       = "#bbbbbb";
static const char col_gray4[]       = "#eeeeee";
static const char col_cyan[]        = "#005577";

static const char *colors[][3] = {
	/*               fg         bg         border */
	[SchemeNorm] = { col_gray3, col_gray1, col_gray2 },
	[SchemeSel]  = { col_gray4, col_cyan,  col_cyan  },
};

static const char *tags[] = {
	"1", "2", "3", "4", "5", "6", "7", "8", "9"
};

static const Rule rules[] = {
	/* class     instance  title  tags mask  isfloating  monitor */
	{ NULL,      NULL,     NULL,  0,         0,          -1 },
};

static const float mfact     = 0.55;
static const int nmaster     = 1;
static const int resizehints = 1;
static const int lockfullscreen = 1;

static const Layout layouts[] = {
	/* symbol     arrange function */
	{ "[]=",      tile },
	{ "><>",      NULL },
	{ "[M]",      monocle },
};

/*
 * Cycle through all layouts.
 *
 * Vanilla dwm's Mod+Space toggles between two layouts.
 * We want Mod+Space to actually cycle through all layouts.
 */
static void
cyclelayout(const Arg *arg)
{
	unsigned int i;
	const Layout *current;

	(void)arg;

	current = selmon->lt[selmon->sellt];

	for (i = 0; i < LENGTH(layouts); i++) {
		if (current == &layouts[i])
			break;
	}

	i = (i + 1) % LENGTH(layouts);

	setlayout(&(Arg){ .v = &layouts[i] });
}

#define MODKEY Mod4Mask

#define TAGKEYS(KEY,TAG) \
	{ MODKEY,                       KEY,      view,           {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask,           KEY,      toggleview,     {.ui = 1 << TAG} }, \
	{ MODKEY|ShiftMask,             KEY,      tag,            {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask|ShiftMask, KEY,      toggletag,      {.ui = 1 << TAG} },

#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

/* Applications */

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

static const Key keys[] = {
	/* modifier                     key        function        argument */

	/* Applications */
	{ MODKEY,                       XK_Return, spawn,          {.v = termcmd} },
	{ MODKEY,                       XK_r,      spawn,          {.v = roficmd} },

	/* Window management */
	{ MODKEY,                       XK_q,      killclient,     {0} },
	{ MODKEY|ShiftMask,             XK_q,      quit,            {0} },

	/* Focus */
	{ MODKEY,                       XK_j,      focusstack,      {.i = +1} },
	{ MODKEY,                       XK_k,      focusstack,      {.i = -1} },

	/* Master count */
	{ MODKEY,                       XK_i,      incnmaster,      {.i = +1} },
	{ MODKEY,                       XK_d,      incnmaster,      {.i = -1} },

	/* Master size */
	{ MODKEY,                       XK_h,      setmfact,        {.f = -0.05} },
	{ MODKEY,                       XK_l,      setmfact,        {.f = +0.05} },

	/* Layout */
	{ MODKEY,                       XK_space,  cyclelayout,      {0} },
	{ MODKEY|ShiftMask,             XK_space,  togglefloating,   {0} },

	/* Fullscreen */
	{ MODKEY,                       XK_f,      spawn,            SHCMD("wmctrl -r :ACTIVE: -b toggle,fullscreen") },

	/* Lock */
	{ MODKEY|ShiftMask,             XK_e,      spawn,            SHCMD("i3lock -c 000000") },

	/* Bar */
	{ MODKEY,                       XK_b,      togglebar,        {0} },

	/* Tags */
	TAGKEYS(                        XK_1,                      0)
	TAGKEYS(                        XK_2,                      1)
	TAGKEYS(                        XK_3,                      2)
	TAGKEYS(                        XK_4,                      3)
	TAGKEYS(                        XK_5,                      4)
	TAGKEYS(                        XK_6,                      5)
	TAGKEYS(                        XK_7,                      6)
	TAGKEYS(                        XK_8,                      7)
	TAGKEYS(                        XK_9,                      8)

	/* Mouse movement / resizing */
};

static const Button buttons[] = {
	/* click                event mask           button          function        argument */
	{ ClkClientWin,          MODKEY,              Button1,        movemouse,     {0} },
	{ ClkClientWin,          MODKEY,              Button3,        resizemouse,   {0} },
};
EOF_DWM

# ------------------------------------------------------------
# Write NixOS configuration.
# ------------------------------------------------------------

cat > "${CONFIG_FILE}" <<'EOF_NIX'
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # ----------------------------------------------------------
  # Basic system
  # ----------------------------------------------------------

  networking.hostName = "nixos";

  networking.networkmanager.enable = true;

  time.timeZone = "America/New_York";

  i18n.defaultLocale = "en_US.UTF-8";

  console.keyMap = "us";

  # ----------------------------------------------------------
  # Boot / firmware
  # ----------------------------------------------------------

  boot.kernelParams = [
    "amd_pstate=active"
  ];

  # ----------------------------------------------------------
  # Graphics
  #
  # The hardware-configuration.nix generated by NixOS remains
  # untouched. Steam also enables the required 32-bit graphics
  # support, but we explicitly enable it here as well.
  # ----------------------------------------------------------

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  # ----------------------------------------------------------
  # X11 + LightDM + dwm
  # ----------------------------------------------------------

  services.xserver = {
    enable = true;

    xkb = {
      layout = "us";
      variant = "";
    };

    displayManager = {
      lightdm = {
        enable = true;
      };

      defaultSession = "none+dwm";

      sessionCommands = ''
        ${pkgs.picom}/bin/picom --daemon &
        ${pkgs.dunst}/bin/dunst &
      '';
    };

    windowManager.dwm = {
      enable = true;
    };
  };

  # ----------------------------------------------------------
  # Customized dwm
  #
  # Nix builds dwm from the normal nixpkgs package but replaces
  # config.def.h with our actual file in /etc/nixos/dwm/.
  # ----------------------------------------------------------

  nixpkgs.overlays = [
    (final: prev: {
      dwm = prev.dwm.overrideAttrs (oldAttrs: {
        configFile = final.writeText
          "dwm-config.def.h"
          (builtins.readFile ./dwm/config.def.h);

        postPatch =
          (oldAttrs.postPatch or "")
          + ''
            cp ${final.writeText "dwm-config.def.h" (builtins.readFile ./dwm/config.def.h)} config.def.h
          '';
      });
    })
  ];

  # ----------------------------------------------------------
  # Audio
  # ----------------------------------------------------------

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;

    alsa = {
      enable = true;
      support32Bit = true;
    };

    pulse.enable = true;
  };

  # ----------------------------------------------------------
  # Bluetooth
  # ----------------------------------------------------------

  hardware.bluetooth.enable = true;

  services.blueman.enable = true;

  # ----------------------------------------------------------
  # Flatpak + XDG Desktop Portal
  # ----------------------------------------------------------

  services.flatpak.enable = true;

  xdg.portal = {
    enable = true;

    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];

    config.common.default = "gtk";
  };

  # ----------------------------------------------------------
  # Steam
  # ----------------------------------------------------------

  nixpkgs.config.allowUnfree = true;

  programs.steam = {
    enable = true;
  };

  # ----------------------------------------------------------
  # Firefox
  # ----------------------------------------------------------

  programs.firefox.enable = true;

  # ----------------------------------------------------------
  # User
  # ----------------------------------------------------------

  users.users.__NIXOS_USER__ = {
    isNormalUser = true;

    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
    ];
  };

  security.sudo.enable = true;

  # ----------------------------------------------------------
  # Desktop / development packages
  # ----------------------------------------------------------

  environment.systemPackages = with pkgs; [

    # Terminal / launcher
    alacritty
    rofi

    # Desktop utilities
    dunst
    picom
    thunar
    pavucontrol
    flameshot
    feh

    # Lock / fullscreen helpers
    i3lock
    wmctrl

    # System utilities
    fastfetch
    btop
    htop
    unzip
    zip
    p7zip
    wget
    curl
    git

    # Development
    gcc
    gnumake
    cmake
    pkg-config

    # X11 development
    libX11
    libXft
    libXinerama
    xorgproto

    # X11 utilities
    xorg.xrandr
    xorg.xset
    xorg.xsetroot
    xorg.xev
    xorg.xprop
    xclip

    # Useful for building / experimenting
    gdb
    gnumake
  ];

  # ----------------------------------------------------------
  # Environment
  # ----------------------------------------------------------

  environment.variables = {
    EDITOR = "nano";
    VISUAL = "nano";
  };

  # ----------------------------------------------------------
  # Nix
  # ----------------------------------------------------------

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Keep the normal NixOS garbage collection behaviour.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # ----------------------------------------------------------
  # State version
  # ----------------------------------------------------------

  system.stateVersion = "__STATE_VERSION__";
}
EOF_NIX

# Replace placeholders safely.
sed -i \
    -e "s/__NIXOS_USER__/${TARGET_USER}/g" \
    -e "s/__STATE_VERSION__/${STATE_VERSION}/g" \
    "${CONFIG_FILE}"

# ------------------------------------------------------------
# Make sure the user owns their home.
# ------------------------------------------------------------

chown "${TARGET_USER}:$(id -gn "${TARGET_USER}")" "${TARGET_HOME}"

# ------------------------------------------------------------
# Validate the Nix configuration before doing anything.
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Validating NixOS configuration"
echo "============================================================"
echo

nixos-rebuild dry-build --show-trace

echo
echo "============================================================"
echo " Building and activating NixOS"
echo "============================================================"
echo

nixos-rebuild switch --show-trace

# ------------------------------------------------------------
# Add Flathub.
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Configuring Flathub"
echo "============================================================"
echo

if command -v flatpak >/dev/null 2>&1; then
    flatpak remote-add \
        --if-not-exists \
        flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
fi

# ------------------------------------------------------------
# Final verification.
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Verification"
echo "============================================================"
echo

echo "NixOS generation:"
nixos-rebuild list-generations | tail -n 3 || true

echo
echo "dwm:"
command -v dwm || true
dwm -v || true

echo
echo "Flatpak:"
flatpak remotes || true

echo
echo "XDG portal:"
systemctl --global status xdg-desktop-portal.service --no-pager 2>/dev/null || true

echo
echo "============================================================"
echo " NixOS + dwm setup complete"
echo "============================================================"
echo
echo "User:       ${TARGET_USER}"
echo "Session:    LightDM -> X11 -> dwm"
echo "Config:     ${CONFIG_FILE}"
echo "dwm config: ${DWM_DIR}/config.def.h"
echo
echo "Your original configuration was backed up to:"
echo "  ${BACKUP_FILE}"
echo
echo "The system will reboot in 10 seconds."
echo "Press Ctrl+C now if you want to inspect anything first."
echo

sleep 10

reboot
