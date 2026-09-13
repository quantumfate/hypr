-- Splits are deterministic on purpose.
--
-- smart_split picked the direction from which quadrant of the tile the cursor
-- was in, so the same action split sideways or downwards depending on where the
-- mouse happened to rest — which is how a 5120x1440 panel ends up holding two
-- very wide, very short windows. force_split 2 puts every new window to the
-- right instead, and preserve_split keeps a split where it was put.
hl.config({
  dwindle = {
    force_split = 2,
    preserve_split = true,
    smart_split = false,
    smart_resizing = true,
    permanent_direction_override = false,
    split_width_multiplier = 0.5,
    use_active_for_splits = true,
    default_split_ratio = 1.25,
    split_bias = 0,
    precise_mouse_move = false,
  },
})

local layout = require("hypr.lib.layout")

-- Directional focus/swap come from the fallback (plain movefocus / swapwindow),
-- which is all dwindle needs there. The tree ops that make dwindle a binary tree
-- live in their own submap: SUPER+x -> d -> key. Each leaf runs and closes the
-- menu (which-key style); escape steps back a level.
layout.register_submap({
  layout = "dwindle",
  key = "d",
  entries = {
    { key = "r", desc = "Dwindle: promote active window to tree root", action = hl.dsp.layout("movetoroot keepfocus") },
    { key = "t", desc = "Dwindle: flip this node's split H<->V", action = hl.dsp.layout("togglesplit") },
    { key = "s", desc = "Dwindle: swap the two children of the split", action = hl.dsp.layout("swapsplit") },
    { key = "p", desc = "Dwindle: preselect where the next window lands", action = hl.dsp.layout("preselect") },
  },
})
