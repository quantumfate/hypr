hl.config({
  cursor = {
    no_warps = true,
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

    -- A sheet on a desk casts a short, tight shadow — enough to lift it off the
    -- wallpaper, not enough to glow. The old 30px range was a halo.
    shadow = {
      enabled = true,
      range = 8,
      render_power = 2,
      offset = { 0, 2 },
      color = "rgba(0000009a)",
    },
  },

  general = {
    -- The edge is what makes it read as a sheet, so it stays crisp and single.
    border_size = 1,
    -- Separation, not decoration: on the 5120x1440 panel these are roughly 1cm
    -- inner and 3.5cm outer at ~110 DPI. Per-monitor overrides live with the
    -- workspace rules; this is the value everything else deviates from.
    --
    -- The top is the exception. The bar already floats clear of the screen edge
    -- and reserves its own height, so a full outer gap on top of that stacks two
    -- margins and leaves a canyon between the bar and the first window.
    gaps_in = 12,
    gaps_out = { top = 8, right = 40, bottom = 40, left = 40 },
    float_gaps = -1,
    layout = "master",
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
    focus_on_activate = true,
    font_family = "Hack Nerd Font Mono",
    size_limits_tiled = true,
    mouse_move_enables_dpms = true,
    middle_click_paste = true,
  },
})
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
