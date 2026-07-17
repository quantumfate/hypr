hl.config({
  scrolling = {
    fullscreen_on_one_column = false,
    column_width = 0.5,
    focus_fit_method = 0,
  },
})

local layout = require("hypr.lib.layout")

-- Scrolling has its own directional focus that moves across columns / within a
-- column. swap_* falls back to directional window.swap.
layout.register("scrolling", {
  focus_left = function()
    hl.dispatch(hl.dsp.layout("focus l"))
  end,
  focus_right = function()
    hl.dispatch(hl.dsp.layout("focus r"))
  end,
  focus_up = function()
    hl.dispatch(hl.dsp.layout("focus u"))
  end,
  focus_down = function()
    hl.dispatch(hl.dsp.layout("focus d"))
  end,
})

-- Scrolling-specific ops: SUPER+x -> s -> key. The colresize leaves use `stay`
-- so you can repeat them without reopening the menu; the rest close on use.
-- NOTE: token names are from the hyprscrolling plugin — adjust to your version
-- (check `hyprctl layouts` / the plugin docs) if any of these no-op.
layout.register_submap({
  layout = "scrolling",
  key = "s",
  entries = {
    { key = "l", desc = "Scrolling: move window to the next column", action = hl.dsp.layout("movewindowto r") },
    { key = "h", desc = "Scrolling: move window to the previous column", action = hl.dsp.layout("movewindowto l") },
    { key = "f", desc = "Scrolling: fit the active column to the viewport", action = hl.dsp.layout("fit active") },
    {
      key = "equal",
      desc = "Scrolling: widen the active column",
      action = hl.dsp.layout("colresize +0.1"),
      stay = true,
      repeating = true,
    },
    {
      key = "minus",
      desc = "Scrolling: narrow the active column",
      action = hl.dsp.layout("colresize -0.1"),
      stay = true,
      repeating = true,
    },
  },
})
