hl.config({
  cursor = {
    no_warps = true,
    -- The granular warp switches this build reads; `no_warps` alone left the
    -- pointer able to follow an explicit monitor focus. A focus change the
    -- user did not ask for must not drag the pointer to another monitor.
    warp_on_change_workspace = 0,
    warp_on_toggle_special = 0,
    warp_on_monitor_change = 0,
  },

  binds = {
    workspace_back_and_forth = false,
    hide_special_on_workspace_change = true,
  },

  decoration = {
    -- Paper, not glass. A sheet has a crisp edge and barely any curve; 6 was
    -- already a compromise and still reads as a soft UI chrome.
    rounding = 3,
    -- Opaque by default: only the roles that opacity.lua's role table lists
    -- (terminals, file/process managers) get thinned, via per-class "override"
    -- rules — anything that renders images or video stays at this 1.
    active_opacity = 1,
    inactive_opacity = 1,
    dim_around = 0.6,
    dim_special = 0.4,

    blur = {
      enabled = true,
      -- Less blur than before: paper is opaque enough that a heavy frost just
      -- muddies what is behind it. Enough to separate, not to dissolve.
      size = 4, -- blur kernel radius
      passes = 2,
      new_optimizations = true,
      xray = false, -- true = blur sees through ALL windows to wallpaper
      ignore_opacity = true, -- blur even fully-opaque regions of windows below
      noise = 0.02, -- subtle film grain hides banding
      contrast = 1.05, -- slightly punch up blurred content
      brightness = 1.0,
      vibrancy = 0.18, -- saturation boost on blurred areas
      vibrancy_darkness = 0.0,
      popups = true, -- blur menus/tooltips too
      popups_ignorealpha = 0.2,
    },

    -- A focused window gets a small drop shadow so it reads as the sheet that
    -- is currently lifted toward the user. The border still carries the accent;
    -- the shadow is only there to separate the active window from a matching
    -- wallpaper or from other sheets. Unfocused windows keep the shadow off via
    -- a dynamic rule, so the lift is focus-specific rather than global weight.
    shadow = {
      enabled = true,
      range = 10,
      render_power = 2,
      color = "rgba(00000033)",
      offset = { 0, 3 },
    },
  },

  general = {
    -- Focus is elevation, not an edge: the shadow above is the one active
    -- indicator, so the border carries no paint at all (size 0). The border
    -- also feeds the geometry the bar mirrors (`hypr/lib/geometry.lua` folds
    -- `general.border_size`), so it stays a config value, not a hardcode.
    border_size = 0,
    -- Separation, not decoration. This is only the boot-time / no-override
    -- default (conf/base.lua's `default_gaps`, the one place gap numbers are
    -- declared) -- every monitor role gets its own, wider, entry in
    -- `geometry_profiles`, applied per workspace by
    -- `hypr/scene/provider.lua`. See `default_gaps`'s comment for why top
    -- stays tighter than the other three sides.
    gaps_in = config.default_gaps.gaps_in,
    gaps_out = config.default_gaps.gaps_out,
    float_gaps = -1,
    -- Scene is the default layout (D3): a workspace opts into `columns`
    -- explicitly, or is left as scene, which frames an undeclared workspace's
    -- windows evenly rather than doing nothing.
    layout = "scene",
    allow_tearing = false,
    resize_on_border = true,
    no_focus_fallback = true,

    snap = {
      enabled = true,
      monitor_gap = 30,
      border_overlap = false,
    },
  },

  -- Grouping is how many terminals share one tile. Project windows are grouped
  -- on open (see windowrules.lua), so a workspace holds one browser beside one
  -- stack of terminals however many are running — and the groupbar is the
  -- indicator that says which of them you are looking at.
  group = {
    auto_group = true,
    groupbar = {
      enabled = true,
      -- Slim: a strip that names the active member, not a tab bar.
      -- Hyprland reserves exactly `height` inside the group's own box (see
      -- hypr/scene/layout.lua), so a group's box stays identical to an
      -- ungrouped tile's — only its content shrinks by this much.
      height = 22,
      font_family = "JetBrainsMono Nerd Font",
      font_size = 11,
      font_weight_active = 700,
      font_weight_inactive = 400,
      render_titles = true,
      -- Only worth the vertical space once there is something to choose between.
      disable_when_only = true,
      -- Filled tabs: the accent block is the active indicator and the title
      -- sits on it (hypr/themes/colors.lua picks crust text for that ground),
      -- with air between tabs and around the strip.
      indicator_height = 0,
      gaps_in = 10,
      gaps_out = 6,
      keep_upper_gap = true,
      -- Pill tabs: every tab is rounded on its own, not one segmented strip.
      gradient_round_only_edges = false,
      rounding = 6,
      gradients = true,
      gradient_rounding = 6,
      -- Scroll over the bar to walk the stack, the same gesture as a tab strip.
      scrolling = true,
    },
  },

  input = {
    kb_layout = "dvorak-custom,us",
    kb_variant = ",dvp", -- index 0: dvorak-custom, index 1: us(dvp) = Programmer Dvorak
    kb_options = config.host.kb_options,
    follow_mouse = 0,
    mouse_refocus = false,
    sensitivity = 0.2,
    touchpad = {
      disable_while_typing = true,
    },
  },

  misc = {
    vrr = 2,
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    -- An application may ask to be focused; it does not get to decide. A
    -- running app raising itself -- a message arriving, a second window
    -- opening, a background job finishing -- pulls the keyboard out from
    -- under whatever the user was actually doing, and an unasked-for focus
    -- change is the most disruptive thing a desk can do. Focus follows what
    -- the user opened, and nothing else.
    --
    -- This is the activation REQUEST only. A window still takes focus when it
    -- opens in the ordinary way, so launching something still lands on it;
    -- the paths that spawn a window nobody asked for suppress that
    -- themselves (drawers, scene companions, a project's template).
    --
    -- `hypr/lib/transition.lua` turns this off for the length of a mode
    -- bracket and restores what it found, so it keeps working either way.
    focus_on_activate = false,
    font_family = "Hack Nerd Font Mono",
    size_limits_tiled = true,
    mouse_move_enables_dpms = true,
    middle_click_paste = true,
  },
})
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
