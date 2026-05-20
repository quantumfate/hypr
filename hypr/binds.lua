local toggle_minimize = require("hypr.lib.minimize")
local bind = require("hypr.lib.bind")

-- TODO: replace for qs ipc
-- hl.bind(config.main_mod .. " + space", hl.dsp.exec_cmd("dms ipc call spotlight toggle"))
-- hl.bind(config.main_mod .. " + V", hl.dsp.exec_cmd("dms ipc call clipboard toggle"))
-- hl.bind(config.main_mod .. " + P", hl.dsp.exec_cmd("dms ipc call processlist focusOrToggle"))
-- hl.bind(config.main_mod .. " + comma", hl.dsp.exec_cmd("dms ipc call settings focusOrToggle"))
-- hl.bind(config.main_mod .. " + N", hl.dsp.exec_cmd("dms ipc call notifications toggle"))
-- hl.bind(config.main_mod .. " + SHIFT + N", hl.dsp.exec_cmd("dms ipc call notepad toggle"))
-- hl.bind(config.main_mod .. " + X", hl.dsp.exec_cmd("dms ipc call powermenu toggle"))

-- === Audio controls ===
bind.audio("RaiseVolume", "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 3%+", "Volume up", nil, true)
bind.audio("LowerVolume", "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 3%-", "Volume down", nil, true)
bind.audio("Mute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", "Mute output")
bind.audio("MicMute", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", "Mute microphone")
bind.audio("Pause", "playerctl play-pause", "Media play/pause")
bind.audio("Play", "playerctl play-pause", "Media play/pause")
bind.audio("Prev", "playerctl previous", "Media previous track")
bind.audio("Next", "playerctl next", "Media next track")
bind.audio("RaiseVolume", "playerctl volume 0.03+", "Media player volume up", { "CTRL" }, true)
bind.audio("LowerVolume", "playerctl volume 0.03-", "Media player volume down", { "CTRL" }, true)

bind.brightness("Up", ",brightness.sh --inc")
bind.brightness("Down", ',brightness.sh --dec ""')

-- === Window management ===
hl.bind(config.main_mod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(config.main_mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(config.main_mod .. " + SHIFT + T", hl.dsp.window.float())

hl.bind(
	config.main_mod .. " + semicolon",
	hl.dsp.window.close("activewindow"),
	{ description = "Close focused window", submap_universal = true }
)

bind.app("return", config.app_cmds.terminal, "Open the Terminal")
bind.app("s", config.app_cmds.tmux, "Open Kitty with Tmux Session")
bind.app("return", config.app_cmds.terminal_float, "Open the floating Terminal", { "SHIFT" })
bind.app("d", config.app_cmds.media_browser, "Open Zen Browser media profile", { "ALT" })
bind.app("b", config.app_cmds.main_browser, "Open the Browser")
bind.app("c", config.app_cmds.calculator, "Open Calculator")
bind.app("m", config.app_cmds.password_manager, "Open Proton Pass")
bind.exec("r", config.app_cmds.app_launcher, {
	description = "Open Application Launcher",
	submap_universal = true,
})

bind.special_workspace("s", "spotify", { "ALT" })
bind.special_workspace("v", "vesktop", { "ALT" })

bind.focus_workspace("TAB", "e-1")
bind.focus_workspace("TAB", "e+1", { "SHIFT" })

bind.bind_workspaces()

bind.move_window_focus("h", "l", "Move window focus to the left")
bind.move_window_focus("l", "r", "Move window focus to the right")
bind.move_window_focus("j", "u", "Move window focus up")
bind.move_window_focus("k", "d", "Move window focus down")

bind.swap_windows("h", "l", "Swap current with the left window", { "SHIFT" })
bind.swap_windows("l", "r", "Swap current with the right window", { "SHIFT" })
bind.swap_windows("j", "u", "Swap current with the window above", { "SHIFT" })
bind.swap_windows("k", "d", "Swap current with the window below", { "SHIFT" })

bind.resize_split("h", -10, 0, { "CTRL" })
bind.resize_split("l", 10, 0, { "CTRL" })
bind.resize_split("j", 0, -10, { "CTRL" })
bind.resize_split("k", 0, 10, { "CTRL" })

-- === Mouse bindings ===
hl.bind(
	config.main_mod .. " + ALT + mouse:272",
	hl.dsp.window.drag(),
	{ description = "Move a window with left click", submap_universal = true, mouse = true }
)
hl.bind(
	config.main_mod .. " + ALT + mouse:273",
	hl.dsp.window.resize(),
	{ description = "Resize a window with right click", submap_universal = true, mouse = true }
)
hl.bind(config.main_mod .. " + ALT + m", function()
	toggle_minimize:toggle_minimize()
end, { description = "Minimize Window", submap_universal = true })

-- === Utility ===
bind.screenshot(config.main_mod .. " + PRINT", "window", "Screenshot current window")
bind.screenshot("PRINT", "output", "Screenshot current output")
bind.screenshot(config.main_mod .. " + SHIFT + PRINT", "region", "Screenshot a selected region")

bind.exec("p", "hyprpicker -a -n", {
	no_main = true,
	mods = { "ALT" },
	description = "Execute hyprpicker to extract hex code",
})

bind.exec("l", "hyprlock -c ~/.config/hypr-chezmoi/hyprlock.conf", {
	mods = { "ALT" },
	description = "Lock the screen",
})
