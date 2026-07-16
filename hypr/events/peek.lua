-- Passive peek cheatsheet.
--
-- Separate from the main cheatsheet (SUPER+/ or the shell submap), which is a
-- focus-grabbing, dimmed, centered modal. This one is hands-off: when you enter
-- a submap and *dwell* there past a delay, a non-interactive contextual panel
-- fades in so you can read the binds while still seeing (and using) the window
-- underneath. The next key press changes the submap, which hides it again.
--
-- All the "what submap am I in" logic comes from the Hyprland event system via
-- hypr/lib/hypr.lua rather than any state we track ourselves — the trigger is
-- clear by design. Rendering (non-focusable layer surface) is quickshell-side:
-- CheatSheetPeek.qml, IPC target `cheatsheetPeek`.
--
-- Seamless across navigation: the panel opens once, after you first dwell in a
-- submap past the delay, and then *stays* open while you traverse nested
-- submaps — it just re-reads the new context (the QML follows the submap live).
-- It only tears down when you land back at root, i.e. when a leaf action exits
-- the tree or you escape out. So descending/moving between submaps never
-- flickers or restarts the timer; only reaching root closes it.
local hypr = require("hypr.lib.hypr")
local qs = require("hypr.lib.qs")

-- Pending show timer; nil once it has fired or been cancelled.
---@type HL.Timer|nil
local pending = nil
-- Whether the panel is currently open, so navigation between submaps neither
-- re-arms the timer nor re-opens what is already there.
local shown = false

local function cancel()
	if pending then
		pending:set_enabled(false)
		pending = nil
	end
end

hypr.on_submap_change(function(submap)
	-- Hyprland reports root as "" (raw event) or "reset" (the dispatcher keyword
	-- we use). Reaching root is the only thing that closes the peek.
	if submap == "" or submap == "reset" then
		cancel()
		if shown then
			qs.call("cheatsheetPeek", "close")
			shown = false
		end
		return
	end

	-- Inside a submap. If the panel is already up, or already counting down, let
	-- it be — navigating deeper just updates the context, seamlessly. Otherwise
	-- this is the first entry into the tree: start the dwell timer.
	if not shown and not pending then
		pending = hypr.oneshot(config.peek_delay_ms, function()
			pending = nil
			shown = true
			qs.call("cheatsheetPeek", "open")
		end)
	end
end)
