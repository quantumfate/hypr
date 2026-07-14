hl.config({
	master = {
		new_status = "inherit",
		orientation = "left",
		new_on_active = "after",
		mfact = 0.70,
		center_master_fallback = "right",
		always_keep_position = false,
		slave_count_for_center_master = 2,
	},
})

local layout = require("hypr.lib.layout")

-- master + monocle are a linear stack: left/down walk the ring one way,
-- right/up the other. swap_* falls back to directional window.swap.
local cycle = {
	focus_left = function()
		hl.dispatch(hl.dsp.layout("cycleprev"))
	end,
	focus_down = function()
		hl.dispatch(hl.dsp.layout("cycleprev"))
	end,
	focus_right = function()
		hl.dispatch(hl.dsp.layout("cyclenext"))
	end,
	focus_up = function()
		hl.dispatch(hl.dsp.layout("cyclenext"))
	end,
}
layout.register("master", cycle)
layout.register("monocle", cycle)

-- Master-specific ops: SUPER+x -> m -> key.
layout.register_submap({
	layout = "master",
	key = "m",
	entries = {
		{ key = "m", desc = "Master: swap active with the master window", action = hl.dsp.layout("swapwithmaster auto") },
		{ key = "f", desc = "Master: focus the master window", action = hl.dsp.layout("focusmaster auto") },
		{ key = "a", desc = "Master: add a master slot", action = hl.dsp.layout("addmaster") },
		{ key = "d", desc = "Master: remove a master slot", action = hl.dsp.layout("removemaster") },
		{ key = "o", desc = "Master: cycle orientation", action = hl.dsp.layout("orientationnext") },
	},
})
