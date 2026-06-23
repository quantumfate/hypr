local dofus_launch = require("hypr.services.dofus.launch")
local common = require("hypr.services.dofus.common")
local team = require("hypr.services.dofus.team")
local swap = require("hypr.services.dofus.swap")

-- Window rules
hl.window_rule({
	match = { initial_class = "Dofus.x64" },
	workspace = "name:gaming",
	center = true,
	content = "game",
	opacity = "1.0 override",
	no_anim = true,
	suppress_event = "fullscreen",
})

hl.workspace_rule({
	workspace = "special:ankama",
	on_created_empty = "gamemoderun ankama-launcher",
})

hl.window_rule({
	match = { initial_class = "Ankama Launcher" },
	workspace = "special:ankama",
})
hl.window_rule({
	match = { class = "Ankama Launcher", title = "overlay" },
	workspace = "name:gaming",
	float = true,
	center = true,
	tag = "+floating-window",
})

-- Enter the Dofus submap
hl.bind(config.main_mod .. " + d", hl.dsp.submap("dofus"))

hl.define_submap("dofus", function()
	hl.bind("escape", hl.dsp.submap("reset"))
	hl.bind("d", function()
		dofus_launch:toggle_enable()
	end)
	hl.bind("a", hl.dsp.exec_cmd("gamemoderun ankama-launcher"))
	hl.bind("SUPER + ALT + a", hl.dsp.workspace.toggle_special("ankama"))
	hl.bind("s", function()
		swap.toggle()
	end)
	hl.bind("plus", function()
		common.select("pioneer")
		hl.dispatch(hl.dsp.submap("team_pioneer"))
	end)
end)

hl.define_submap("team_pioneer", function()
	for i = 1, 8 do
		hl.bind("F" .. i, function()
			team.activate(common.team(), i)
		end)
	end
	hl.bind("F23", function()
		team.iterate(common.team(), false)
	end)
	hl.bind(config.main_mod .. " + F23", function()
		team.iterate(common.team(), true)
	end)
	hl.bind("right", function()
		team.iterate(common.team(), false)
	end)
	hl.bind("left", function()
		team.iterate(common.team(), true)
	end)
	hl.bind("mouse:274", function()
		team.press(common.team())
	end)
	hl.bind("up", function()
		team.press(common.team())
	end)
	hl.bind("SHIFT + escape", hl.dsp.submap("dofus"))
	hl.bind(config.main_mod .. " + F10", function()
		team.double_click_start()
	end)
	hl.bind(config.main_mod .. " + F11", function()
		team.double_click_stop()
	end, { release = true, transparent = true })
end)
