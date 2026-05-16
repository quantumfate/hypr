-- Dofus gaming window rules & submaps.
-- Ported from the formerly chezmoi-managed dofus-binds.conf.
--
-- MACHINE-SPECIFIC: only relevant on machines where you play Dofus. The bound
-- scripts live in an external repo (gitlab/quantumfate/dofus-scripts).

local mainMod = "SUPER"
local dofus_scripts = "~/.local/share/own-scripts/gitlab/quantumfate/dofus-scripts"
local dofus_launch = require("conf.dofus.launch")
local colors = require("themes.macchiato")

-- Window rules
hl.window_rule({
	match = { initial_class = "Dofus.x64" },
	workspace = "5",
	float = true,
	center = true,
	content = "game",
	opacity = "1.0 override",
	no_anim = true,
	suppress_event = "fullscreen",
})
hl.window_rule({
	match = { initial_class = "Ankama Launcher" },
	workspace = "5",
	center = true,
	size = { 2000, 1200 },
	float = true,
})
hl.window_rule({
	match = { class = "Ankama Launcher", title = "overlay" },
	workspace = "5",
	float = true,
	center = true,
	tag = "+floating-window",
})

-- Enter the Dofus submap
hl.bind(mainMod .. " + d", hl.dsp.submap("dofus"))

hl.define_submap("dofus", function()
	hl.bind("escape", hl.dsp.submap("reset"))
	hl.bind("d", function()
		dofus_launch:toggle_enable()
	end)
	hl.bind("s", hl.dsp.exec_cmd(dofus_scripts .. "/dofus_swap_toggle.sh"))
	hl.bind("plus", hl.dsp.submap("team_pioneer"))
end)

hl.define_submap("team_pioneer", function()
	for i = 1, 8 do
		hl.bind("F" .. i, hl.dsp.exec_cmd(dofus_scripts .. "/wrap_action.sh --activate " .. (i - 1)))
	end
	-- Scroll direction is inverted
	hl.bind("F23", hl.dsp.exec_cmd(dofus_scripts .. "/wrap_action.sh --down --pioneer"))
	hl.bind(mainMod .. " + F23", hl.dsp.exec_cmd(dofus_scripts .. "/wrap_action.sh --up --pioneer"))
	hl.bind("right", hl.dsp.exec_cmd(dofus_scripts .. "/wrap_action.sh --down --pioneer"))
	hl.bind("left", hl.dsp.exec_cmd(dofus_scripts .. "/wrap_action.sh --up --pioneer"))
	hl.bind("mouse:274", hl.dsp.exec_cmd(dofus_scripts .. "/wrap_action.sh --press --pioneer"))
	hl.bind("SHIFT + escape", hl.dsp.submap("dofus"))
	hl.bind(mainMod .. " + F10", hl.dsp.exec_cmd("bash " .. dofus_scripts .. "/double_click.sh &"))
	hl.bind(mainMod .. " + F11", hl.dsp.exec_cmd("pkill -f double_click.sh"), { release = true, transparent = true })
end)
