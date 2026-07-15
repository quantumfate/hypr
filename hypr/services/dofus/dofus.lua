local dofus_launch = require("hypr.services.dofus.launch")
local common = require("hypr.services.dofus.common")
local team = require("hypr.services.dofus.team")
local swap = require("hypr.services.dofus.swap")
local ipc = require("hypr.services.dofus.ipc")
local submap = require("hypr.lib.submap")

-- Window rules live in hypr/windowrules.lua; the special:ankama workspace (with
-- its on_created_empty launcher) lives in the host workspace_specs.

-- Team control is modal: keys are pressed repeatedly while the submap stays
-- open (sticky), so leaves don't close it. Nested under the Dofus submap.
local team_pioneer_entries = {}
for i = 1, 8 do
	team_pioneer_entries[i] = {
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
	team_pioneer_entries[#team_pioneer_entries + 1] = e
end

submap.tree({
	mods = { config.main_mod, "d" },
	name = "dofus",
	desc = "Dofus",
	sticky = true,
	-- Entering/leaving the Dofus tree shows/hides the Quickshell team panel.
	on_enter = function()
		ipc.panel("show")
	end,
	on_leave = function()
		ipc.panel("hide")
	end,
	entries = {
		{
			key = "space",
			desc = "Toggle team panel",
			action = function()
				ipc.panel("toggle")
			end,
		},
		{
			key = "d",
			desc = "Toggle launch-on-open",
			action = function()
				dofus_launch:toggle_enable()
			end,
		},
		{ key = "a", desc = "Launch Ankama launcher", action = hl.dsp.exec_cmd("gamemoderun ankama-launcher") },
		{
			key = "s",
			desc = "Toggle swap",
			action = function()
				swap.toggle()
			end,
		},
		{
			key = "plus",
			name = "team_pioneer",
			desc = "Pioneer team",
			action = function()
				common.select("pioneer")
			end,
			-- Push the selection into the running UI so the panel reflects the
			-- active team submap immediately (store write is the durable truth).
			on_enter = function()
				ipc.select("pioneer")
			end,
			entries = team_pioneer_entries,
		},
	},
})
