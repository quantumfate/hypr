local dofus_launch = require("hypr.services.dofus.launch")
local common = require("hypr.services.dofus.common")
local team = require("hypr.services.dofus.team")
local swap = require("hypr.services.dofus.swap")
local ipc = require("hypr.services.dofus.ipc")
local submap = require("hypr.lib.submap")

-- Window rules live in hypr/windowrules.lua; the special:ankama workspace (with
-- its on_created_empty launcher) lives in the host workspace_specs.

-- The Dofus submap only launches Dofus; ALL team interaction is delegated to
-- per-team submaps. Entering a team's submap is the single, canonical way to
-- select that team (durable store write + instant UI push), and inside it a
-- dedicated key toggles the Quickshell widget for adjusting that team's order.

-- Team interaction entries. They act on the *selected* team (set on submap
-- enter), so one set is reused by every team submap. Sticky: keys repeat while
-- the submap stays open.
local team_entries = {
	{
		key = "space",
		desc = "Toggle order widget",
		action = function()
			ipc.panel("toggle")
		end,
	},
}
for i = 1, 8 do
	team_entries[#team_entries + 1] = {
		key = "F" .. i,
		desc = "Activate team member " .. i,
		action = function()
			team.activate(common.team(), i)
		end,
	}
end
for _, e in ipairs({
	{
		key = "right",
		desc = "Next team member",
		action = function()
			team.iterate(common.team(), false)
		end,
	},
	{
		key = "F23",
		desc = "Next team member",
		action = function()
			team.iterate(common.team(), false)
		end,
	},
	{
		key = "left",
		desc = "Previous team member",
		action = function()
			team.iterate(common.team(), true)
		end,
	},
	{
		key = "F23",
		mods = { config.main_mod },
		desc = "Previous team member",
		action = function()
			team.iterate(common.team(), true)
		end,
	},
	{
		key = "up",
		desc = "Press current member",
		action = function()
			team.press(common.team())
		end,
	},
	{
		key = "mouse:274",
		desc = "Press current member",
		action = function()
			team.press(common.team())
		end,
	},
	{
		key = "s",
		desc = "Toggle swap",
		action = function()
			swap.toggle()
		end,
	},
	{
		key = "F10",
		mods = { config.main_mod },
		desc = "Start double-click",
		action = function()
			team.double_click_start()
		end,
	},
	{
		key = "F11",
		mods = { config.main_mod },
		desc = "Stop double-click",
		opts = { release = true, transparent = true },
		action = function()
			team.double_click_stop()
		end,
	},
}) do
	team_entries[#team_entries + 1] = e
end

-- Build a team submap group. Entering it selects `team_key` everywhere:
-- common.select writes the store (Lua-side durable truth) and ipc.select pushes
-- it to the running UI so the widget reflects the team immediately.
---@param key string trigger key within the Dofus submap
---@param name string submap name
---@param team_key string team key in the store
---@param desc string cheatsheet label
---@return SubmapEntry
local function team_group(key, name, team_key, desc)
	return {
		key = key,
		name = name,
		desc = desc,
		action = function()
			common.select(team_key)
		end,
		on_enter = function()
			ipc.select(team_key)
		end,
		entries = team_entries,
	}
end

submap.tree({
	mods = { config.main_mod, "d" },
	name = "dofus",
	desc = "Dofus",
	sticky = true,
	-- Leaving the whole tree hides the order widget (it is opened on demand from
	-- inside a team submap, not automatically).
	on_leave = function()
		ipc.panel("hide")
	end,
	entries = {
		{
			key = "d",
			desc = "Toggle launch-on-open",
			action = function()
				dofus_launch:toggle_enable()
			end,
		},
		{ key = "a", desc = "Launch Ankama launcher", action = hl.dsp.exec_cmd("gamemoderun ankama-launcher") },
		-- One group per team. Add a team = add a line here (and its roster to the
		-- store); everything else is shared.
		team_group("p", "team_pioneer", "pioneer", "Pioneer team"),
	},
})
