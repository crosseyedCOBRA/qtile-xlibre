```c
/* Custom dwm configuration for NixOS */

static const unsigned int borderpx  = 1;
static const unsigned int snap      = 32;
static const int showbar            = 1;
static const int topbar             = 1;

static const char *fonts[] = {
	"JetBrains Mono:size=10"
};

static const char col_gray1[] = "#222222";
static const char col_gray2[] = "#444444";
static const char col_gray3[] = "#bbbbbb";
static const char col_gray4[] = "#eeeeee";
static const char col_cyan[]  = "#005577";

static const char *colors[][3] = {
	[SchemeNorm] = { col_gray3, col_gray1, col_gray2 },
	[SchemeSel]  = { col_gray4, col_cyan,  col_cyan  },
};

static const char *tags[] = {
	"1", "2", "3", "4", "5", "6", "7", "8", "9"
};

static const Rule rules[] = {
	{ NULL, NULL, NULL, 0, 0, -1 },
};

static const float mfact = 0.55;
static const int nmaster = 1;
static const int resizehints = 1;
static const int lockfullscreen = 1;

static const Layout layouts[] = {
	{ "[]=", tile },
	{ "><>", NULL },
	{ "[M]", monocle },
};

/* Cycle through all layouts with Mod+Space */
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
	{ MODKEY, KEY, view, {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask, KEY, toggleview, {.ui = 1 << TAG} }, \
	{ MODKEY|ShiftMask, KEY, tag, {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask|ShiftMask, KEY, toggletag, {.ui = 1 << TAG} },

#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

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
	/* Applications */
	{ MODKEY, XK_Return, spawn, {.v = termcmd} },
	{ MODKEY, XK_r, spawn, {.v = roficmd} },

	/* Window management */
	{ MODKEY, XK_q, killclient, {0} },
	{ MODKEY|ShiftMask, XK_q, quit, {0} },

	/* Focus */
	{ MODKEY, XK_j, focusstack, {.i = +1} },
	{ MODKEY, XK_k, focusstack, {.i = -1} },

	/* Master count */
	{ MODKEY, XK_i, incnmaster, {.i = +1} },
	{ MODKEY, XK_d, incnmaster, {.i = -1} },

	/* Master size */
	{ MODKEY, XK_h, setmfact, {.f = -0.05} },
	{ MODKEY, XK_l, setmfact, {.f = +0.05} },

	/* Layout */
	{ MODKEY, XK_space, cyclelayout, {0} },
	{ MODKEY|ShiftMask, XK_space, togglefloating, {0} },

	/* Fullscreen */
	{ MODKEY, XK_f, spawn,
		SHCMD("wmctrl -r :ACTIVE: -b toggle,fullscreen") },

	/* Lock */
	{ MODKEY|ShiftMask, XK_e, spawn,
		SHCMD("i3lock -c 000000") },

	/* Bar */
	{ MODKEY, XK_b, togglebar, {0} },

	/* Workspaces */
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

static const Button buttons[] = {
	{ ClkClientWin, MODKEY, Button1, movemouse, {0} },
	{ ClkClientWin, MODKEY, Button3, resizemouse, {0} },
};
```
