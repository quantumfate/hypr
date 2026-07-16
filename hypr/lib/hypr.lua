local M = {}

-- Thin helpers over the Hyprland runtime API for *flat* reactions — logic that
-- only cares about "what is true right now", not about our submap navigation
-- tree. Contrast hypr/lib/submap.lua, which owns a stack because back/exit are
-- nesting-aware (a parent stays logically entered while you're in its child).
-- Hyprland's `keybinds.submap` event is flat: it reports the active submap, not
-- how you got there. So it is the right tool for things like the passive peek
-- cheatsheet, and the wrong tool for the submap stack.

-- Subscribers notified on every submap transition, with the new submap name
-- ("" at root). Registered via M.on_submap_change.
---@type fun(submap: string)[]
local submap_subs = {}
-- Last submap we saw, to suppress duplicate events and detect real changes.
local last_submap = nil

hl.on("keybinds.submap", function()
	local cur = hl.get_current_submap() -- "" at root/global
	if cur == last_submap then
		return
	end
	last_submap = cur
	for _, cb in ipairs(submap_subs) do
		cb(cur)
	end
end)

---React to submap changes. `cb` gets the new submap name ("" = root). Fires on
---every transition, in registration order.
---@param cb fun(submap: string)
function M.on_submap_change(cb)
	submap_subs[#submap_subs + 1] = cb
end

---A one-shot timer that runs `cb` after `ms` milliseconds. Returns the handle
---so callers can cancel (`:set_enabled(false)`) or re-arm (`:set_timeout(ms)`).
---@param ms integer
---@param cb fun()
---@return HL.Timer
function M.oneshot(ms, cb)
	return hl.timer(cb, { timeout = ms, type = "oneshot" })
end

return M
