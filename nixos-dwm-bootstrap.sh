```bash
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
 * We want Mod+Space to cycle through all layouts.
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
	{ MODKEY,                       XK_space,  cyclelayout,     {0} },
	{ MODKEY|ShiftMask,             XK_space,  togglefloating,  {0} },

	/* Fullscreen */
	{ MODKEY,                       XK_f,      spawn,
		SHCMD("wmctrl -r :ACTIVE: -b toggle,fullscreen") },

	/* Lock */
	{ MODKEY|ShiftMask,             XK_e,      spawn,
		SHCMD("i3lock -c 000000") },

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
	TAGKEYS(                        XK_8_
```
