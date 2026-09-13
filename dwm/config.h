/* dwm config.h - initial custom configuration */

static const int borderpx = 1;
static const int snap = 32;
static const int showbar = 1;
static const int topbar = 1;

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

static const unsigned int alphas[][3] = {
    [SchemeNorm] = { OPAQUE, OPAQUE, OPAQUE },
    [SchemeSel]  = { OPAQUE, OPAQUE, OPAQUE },
};

static const Rule rules[] = {
    /* class      instance    title       tags mask     isfloating   monitor */
    { NULL,       NULL,       NULL,       0,           0,           -1 },
};

static const float mfact = 0.55;
static const int nmaster = 1;
static const int resizehints = 1;

static const Layout layouts[] = {
    { "[]=",      tile },
    { "><>",      NULL },
    { "[M]",      monocle },
};

/* commands */

static char dmenumon[2] = "0";

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

static const char *lockcmd[] = {
    "loginctl",
    "lock-session",
    NULL
};

#define MODKEY Mod4Mask

#define TAGKEYS(KEY,TAG) \
    { MODKEY,                       KEY,      view,           {.ui = 1 << TAG} }, \
    { MODKEY|ControlMask,           KEY,      toggleview,     {.ui = 1 << TAG} }, \
    { MODKEY|ShiftMask,             KEY,      tag,            {.ui = 1 << TAG} }, \
    { MODKEY|ControlMask|ShiftMask, KEY,      toggletag,      {.ui = 1 << TAG} },

static const Key keys[] = {
    /* modifier                     key        function        argument */

    { MODKEY,                       XK_Return, spawn,          {.v = termcmd} },
    { MODKEY,                       XK_r,      spawn,          {.v = roficmd} },

    { MODKEY,                       XK_q,      killclient,     {0} },
    { MODKEY|ShiftMask,             XK_q,      quit,            {1} },

    { MODKEY,                       XK_j,      focusstack,     {.i = +1} },
    { MODKEY,                       XK_k,      focusstack,     {.i = -1} },

    { MODKEY,                       XK_i,      incnmaster,     {.i = +1} },
    { MODKEY,                       XK_d,      incnmaster,     {.i = -1} },

    { MODKEY,                       XK_h,      setmfact,       {.f = -0.05} },
    { MODKEY,                       XK_l,      setmfact,       {.f = +0.05} },

    { MODKEY,                       XK_space,  setlayout,      {0} },

    { MODKEY|ShiftMask,             XK_space,  togglefloating, {0} },

    { MODKEY,                       XK_f,      togglefullscr,  {0} },

    { MODKEY|ShiftMask,             XK_e,      spawn,           {.v = lockcmd} },

    TAGKEYS(                        XK_1,                      0)
    TAGKEYS(                        XK_2,                      1)
    TAGKEYS(                        XK_3,                      2)
    TAGKEYS(                        XK_4,                      3)
    TAGKEYS(                        XK_5,                      4)
    TAGKEYS(                        XK_6,                      5)
    TAGKEYS(                        XK_7,                      6)
    TAGKEYS(                        XK_8,                      7)
    TAGKEYS(                        XK_9,                      8)
};

static const Button buttons[] = {
    /* click                event mask      button          function        argument */
    { ClkLtSymbol,          0,              Button1,        setlayout,      {0} },
    { ClkLtSymbol,          0,              Button3,        setlayout,      {0} },
    { ClkStatusText,        0,              Button2,        spawn,          {.v = termcmd} },
    { ClkClientWin,         MODKEY,         Button1,        movemouse,      {0} },
    { ClkClientWin,         MODKEY,         Button3,        resizemouse,    {0} },
};
