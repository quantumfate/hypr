local toggle_minimize = require("hypr.lib.minimize")
local bind = require("hypr.lib.bind")
local notify = require("hypr.lib.notify")

-- === Audio controls ===
bind.audio("RaiseVolume", ",volume.sh --inc", "Volume up", nil, true)
bind.audio("LowerVolume", ",volume.sh --dec", "Volume down", nil, true)
bind.audio("Mute", ",volume.sh --toggle", "Mute output")
bind.audio("MicMute", ",volume.sh --toggle-mic", "Mute microphone")
bind.audio("Pause", ",player.sh --play-pause", "Media play/pause")
bind.audio("Play", ",player.sh --play-pause", "Media play/pause")
bind.audio("Prev", ",player.sh --prev", "Media previous track")
bind.audio("Next", ",player.sh --next", "Media next track")
bind.audio("RaiseVolume", ",player.sh --inc", "Media player volume up", { config.tertiary_mod }, true)
bind.audio("LowerVolume", ",player.sh --dec", "Media player volume down", { config.tertiary_mod }, true)

bind.brightness("Up", ",brightness.sh --inc")
bind.brightness("Down", ',brightness.sh --dec ""')

-- === Window management ===
hl.bind(
	bind.parse_mods({ config.main_mod, config.tertiary_mod }) .. " + M",
	hl.dsp.window.fullscreen({ mode = "maximized" })
)
hl.bind(
	bind.parse_mods({ config.main_mod, config.tertiary_mod }) .. " + F",
	hl.dsp.window.fullscreen({ mode = "fullscreen" })
)
hl.bind(bind.parse_mods({ config.main_mod, config.tertiary_mod }) .. " + T", hl.dsp.window.float())

hl.bind(
	config.main_mod .. " + semicolon",
	hl.dsp.window.close("activewindow"),
	{ description = "Close focused window", submap_universal = true }
)

bind.app("return", config.app_cmds.terminal, "Open the Terminal", { config.main_mod })
bind.app(
	"return",
	config.app_cmds.terminal_float,
	"Open the floating Terminal",
	{ config.main_mod, config.primary_mod }
)
bind.app("s", config.app_cmds.tmux, "Open Kitty with Tmux Session", { config.main_mod })
bind.exec("r", config.app_cmds.app_launcher, {
	description = "Open Application Launcher",
})

bind.supmap({ config.main_mod, "a" }, "applications", function()
	bind.app("d", config.app_cmds.media_browser, "Open Zen Browser media profile")
	bind.app("b", config.app_cmds.main_browser, "Open the Browser")
	bind.app("d", config.app_cmds.dev_browser, "Open the dev Browser", { config.primary_mod })
	bind.app("c", config.app_cmds.calculator, "Open Calculator")
	bind.app("m", config.app_cmds.password_manager, "Open Proton Pass")
	bind.app("v", config.app_cmds.volume_control, "Open Wiremix")
	bind.app("f", config.app_cmds.file_manager, "Open Yazi")
end)

bind.supmap({ config.main_mod, "w" }, "special-ws", function()
	bind.special_workspace({ "s" }, "music")
	bind.special_workspace({ "v" }, "comms")
	bind.special_workspace({ "l" }, "launcher")
end)

bind.focus_workspace("TAB", "e-1")
bind.focus_workspace("TAB", "e+1", { config.secondary_mod })

bind.bind_workspaces()

bind.move_window_focus({ config.main_mod, "h" }, "l", "Move window focus to the left")
bind.move_window_focus({ config.main_mod, "l" }, "r", "Move window focus to the right")
bind.move_window_focus({ config.main_mod, "j" }, "u", "Move window focus up")
bind.move_window_focus({ config.main_mod, "k" }, "d", "Move window focus down")

bind.swap_windows({ config.main_mod, config.secondary_mod, "h" }, "l", "Swap current with the left window")
bind.swap_windows({ config.main_mod, config.secondary_mod, "l" }, "r", "Swap current with the right window")
bind.swap_windows({ config.main_mod, config.secondary_mod, "j" }, "u", "Swap current with the window above")
bind.swap_windows({ config.main_mod, config.secondary_mod, "k" }, "d", "Swap current with the window below")

bind.supmap({ config.main_mod, config.secondary_mod, "r" }, "window-management", function()
	bind.resize_split("h", -10, 0)
	bind.resize_split("l", 10, 0)
	bind.resize_split("j", 0, -10)
	bind.resize_split("k", 0, 10)

	bind.resize_split("h", -20, 0, { config.tertiary_mod })
	bind.resize_split("l", 20, 0, { config.tertiary_mod })
	bind.resize_split("j", 0, -20, { config.tertiary_mod })
	bind.resize_split("k", 0, 20, { config.tertiary_mod })

	hl.bind(bind.parse_mods({ "e" }), function()
		local layouts = { "scrolling", "dwindle", "master", "monocle" }
		local workspace = hl.get_active_workspace()
		if hl.get_active_special_workspace() then
			workspace = hl.get_active_special_workspace()
		end

		local next_layout = "dwindle"

		if not workspace then
			return
		end

		for i = 1, #layouts do
			if layouts[i] == workspace.tiled_layout then
				local next_layout_idx = (i % #layouts) + 1
				next_layout = layouts[next_layout_idx]
				break
			end
		end

		if workspace.special then
			hl.workspace_rule({ workspace = tostring(workspace.name), layout = next_layout })
		else
			hl.workspace_rule({ workspace = tostring(workspace.id), layout = next_layout })
		end
	end)
end)

-- === Mouse bindings ===

hl.bind(
	config.main_mod .. " + " .. config.tertiary_mod .. " + mouse:272",
	hl.dsp.window.drag(),
	{ description = "Move a window with left click", submap_universal = true, mouse = true }
)
hl.bind(config.main_mod .. " + " .. config.tertiary_mod .. " + m", function()
	toggle_minimize:toggle_minimize()
end, { description = "Minimize Window", submap_universal = true })

-- === Utility ===
bind.screenshot(config.main_mod .. " + PRINT", "window", "Screenshot current window")
bind.screenshot("PRINT", "output", "Screenshot current output")
bind.screenshot(
	config.main_mod .. " + " .. config.secondary_mod .. " + PRINT",
	"region",
	"Screenshot a selected region"
)

local kb_layouts = { "Dvorak (custom)", "Programmer Dvorak" }
local kb_idx = 1
bind.exec("space", function()
	hl.dispatch(hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))
	kb_idx = kb_idx % #kb_layouts + 1
	notify:notify("Keyboard layout: " .. kb_layouts[kb_idx], 2000, notify.level.INFO)
end, {
	description = "Toggle keyboard layout (dvorak-custom / programmer dvorak)",
	submap_universal = true,
	locked = true,
})

bind.exec("p", "hyprpicker -a -n", {
	no_main = true,
	mods = { config.tertiary_mod },
	description = "Execute hyprpicker to extract hex code",
})

bind.exec("slash", ",cheatsheet.sh", {
	description = "Show keybind cheatsheet",
	submap_universal = true,
})
