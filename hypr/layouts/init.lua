local layout = require("hypr.lib.layout")

-- Default behaviour, used by any layout that doesn't register its own handler
-- for an action. Directional focus/swap works for every simple tiling layout;
-- feature-rich layouts (dwindle, scrolling, master) override below in their
-- own files where the behaviour is nuanced.
layout.register_fallback({
	focus_left = function()
		hl.dispatch(hl.dsp.focus({ direction = "l" }))
	end,
	focus_right = function()
		hl.dispatch(hl.dsp.focus({ direction = "r" }))
	end,
	focus_up = function()
		hl.dispatch(hl.dsp.focus({ direction = "u" }))
	end,
	focus_down = function()
		hl.dispatch(hl.dsp.focus({ direction = "d" }))
	end,
	swap_left = function()
		hl.dispatch(hl.dsp.window.swap({ direction = "l" }))
	end,
	swap_right = function()
		hl.dispatch(hl.dsp.window.swap({ direction = "r" }))
	end,
	swap_up = function()
		hl.dispatch(hl.dsp.window.swap({ direction = "u" }))
	end,
	swap_down = function()
		hl.dispatch(hl.dsp.window.swap({ direction = "d" }))
	end,
})

require("hypr.layouts.scrolling")
require("hypr.layouts.master")
require("hypr.layouts.dwindle")
