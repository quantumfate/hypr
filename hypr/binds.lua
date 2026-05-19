local toggle_minimize = require("hypr.lib.minimize")

-- === Application launchers ===
-- TODO: replace for qs ipc
-- hl.bind(config.main_mod .. " + space", hl.dsp.exec_cmd("dms ipc call spotlight toggle"))
-- hl.bind(config.main_mod .. " + V", hl.dsp.exec_cmd("dms ipc call clipboard toggle"))
-- hl.bind(config.main_mod .. " + P", hl.dsp.exec_cmd("dms ipc call processlist focusOrToggle"))
-- hl.bind(config.main_mod .. " + comma", hl.dsp.exec_cmd("dms ipc call settings focusOrToggle"))
-- hl.bind(config.main_mod .. " + N", hl.dsp.exec_cmd("dms ipc call notifications toggle"))
-- hl.bind(config.main_mod .. " + SHIFT + N", hl.dsp.exec_cmd("dms ipc call notepad toggle"))
-- hl.bind(config.main_mod .. " + X", hl.dsp.exec_cmd("dms ipc call powermenu toggle"))

-- === Cheat sheet ===
hl.bind(config.main_mod .. " + SHIFT + Slash", hl.dsp.exec_cmd("dms ipc call keybinds toggle hyprland"))

-- === Security ===
hl.bind(config.main_mod .. " + ALT + L", hl.dsp.exec_cmd("dms ipc call lock lock"))
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd("dms ipc call processlist focusOrToggle"))

-- === Audio controls ===
-- TODO: replace with script
-- hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("dms ipc call audio increment 3"), { locked = true, repeating = true })
-- hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("dms ipc call audio decrement 3"), { locked = true, repeating = true })
-- hl.bind("XF86AudioMute", hl.dsp.exec_cmd("dms ipc call audio mute"), { locked = true })
-- hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("dms ipc call audio micmute"), { locked = true })
-- hl.bind("XF86AudioPause", hl.dsp.exec_cmd("dms ipc call mpris playPause"), { locked = true })
-- hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("dms ipc call mpris playPause"), { locked = true })
-- hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("dms ipc call mpris previous"), { locked = true })
-- hl.bind("XF86AudioNext", hl.dsp.exec_cmd("dms ipc call mpris next"), { locked = true })
-- hl.bind(
-- 	"CTRL + XF86AudioRaiseVolume",
-- 	hl.dsp.exec_cmd("dms ipc call mpris increment 3"),
-- 	{ locked = true, repeating = true }
-- )
-- hl.bind(
-- 	"CTRL + XF86AudioLowerVolume",
-- 	hl.dsp.exec_cmd("dms ipc call mpris decrement 3"),
-- 	{ locked = true, repeating = true }
-- )

-- === Brightness controls ===
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(",brightness.sh --inc"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(',brightness.sh --dec ""'), { locked = true, repeating = true })

-- === Window management ===
hl.bind(config.main_mod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(config.main_mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(config.main_mod .. " + SHIFT + T", hl.dsp.window.float())

-- === Terminal ===
hl.bind(
	config.main_mod .. " + return",
	hl.dsp.exec_cmd("uwsm app -- " .. config.app_cmds.terminal),
	{ description = "Open the Terminal", submap_universal = true }
)
hl.bind(
	config.main_mod .. " + s",
	hl.dsp.exec_cmd("uwsm app -- " .. config.app_cmds.tmux),
	{ description = "Open Kitty with Tmux Session", submap_universal = true }
)
hl.bind(
	config.main_mod .. " + SHIFT + return",
	hl.dsp.exec_cmd("uwsm app -- " .. config.app_cmds.terminal_float),
	{ description = "Open the Terminal", submap_universal = true }
)
hl.bind(
	config.main_mod .. " + ALT + d",
	hl.dsp.exec_cmd("uwsm-app -- " .. config.app_cmds.media_browser),
	{ description = "Open Zen Browser media profile", submap_universal = true }
)

-- === Applications ===
hl.bind(
	config.main_mod .. " + semicolon",
	hl.dsp.window.close("activewindow"),
	{ description = "Close focused window", submap_universal = true }
)
hl.bind(
	config.main_mod .. " + b",
	hl.dsp.exec_cmd("uwsm app -- " .. config.app_cmds.main_browser),
	{ description = "Open the Browser", submap_universal = true }
)
hl.bind(
	config.main_mod .. " + c",
	hl.dsp.exec_cmd("uwsm app -- " .. config.app_cmds.calculator),
	{ description = "Open Calculator", submap_universal = true }
)
hl.bind(
	config.main_mod .. " + m",
	hl.dsp.exec_cmd("uwsm app -- " .. config.app_cmds.password_manager),
	{ description = "Open Proton Pass", submap_universal = true }
)
hl.bind(
	config.main_mod .. " + r",
	hl.dsp.exec_cmd(config.app_cmds.app_launcher),
	{ description = "Open Application Launcher", submap_universal = true }
)

-- === Special workspaces ===
hl.bind(
	config.main_mod .. " + ALT + s",
	hl.dsp.workspace.toggle_special("spotify"),
	{ description = "Toggle Special Workspace spotify", submap_universal = true }
)
hl.bind(
	config.main_mod .. " + ALT + v",
	hl.dsp.workspace.toggle_special("vesktop"),
	{ description = "Toggle Special Workspace vesktop", submap_universal = true }
)

-- === Workspaces ===
hl.bind(
	config.main_mod .. " + TAB",
	hl.dsp.focus({ workspace = "e-1" }),
	{ description = "Previous workspace", submap_universal = true }
)
hl.bind(
	config.main_mod .. " + SHIFT + TAB",
	hl.dsp.focus({ workspace = "e+1" }),
	{ description = "Next workspace", submap_universal = true }
)

for i, key in ipairs(config.workspaces.workspace_keys) do
	if config.workspaces.workspace_specs[i] then
		hl.bind(
			config.main_mod .. " + " .. key,
			hl.dsp.focus({ workspace = i }),
			{ description = "Switch to workspace " .. i, submap_universal = true }
		)
		hl.bind(
			config.main_mod .. " + SHIFT + " .. key,
			hl.dsp.window.move({ workspace = i, follow = true }),
			{ description = "Move focused to workspace " .. i, submap_universal = true }
		)
	end
end

-- === Window focus / swap / resize ===
hl.bind(config.main_mod .. " + h", hl.dsp.focus({ direction = "l" }), { description = "Move window focus to the left" })
hl.bind(
	config.main_mod .. " + l",
	hl.dsp.focus({ direction = "r" }),
	{ description = "Move window focus to the right" }
)
hl.bind(config.main_mod .. " + j", hl.dsp.focus({ direction = "u" }), { description = "Move window focus up" })
hl.bind(config.main_mod .. " + k", hl.dsp.focus({ direction = "d" }), { description = "Move window focus down" })

hl.bind(
	config.main_mod .. " + SHIFT + h",
	hl.dsp.window.swap({ direction = "l" }),
	{ description = "Swap current window with the window to the left" }
)
hl.bind(
	config.main_mod .. " + SHIFT + l",
	hl.dsp.window.swap({ direction = "r" }),
	{ description = "Swap current window with the window to the right" }
)
hl.bind(
	config.main_mod .. " + SHIFT + j",
	hl.dsp.window.swap({ direction = "u" }),
	{ description = "Swap current window with the lower window" }
)
hl.bind(
	config.main_mod .. " + SHIFT + k",
	hl.dsp.window.swap({ direction = "d" }),
	{ description = "Swap current window with the upper window" }
)

hl.bind(
	config.main_mod .. " + CTRL + h",
	hl.dsp.window.resize({ x = -10, y = 0, relative = true }),
	{ description = "Resize vertical by -10", repeating = true }
)
hl.bind(
	config.main_mod .. " + CTRL + l",
	hl.dsp.window.resize({ x = 10, y = 0, relative = true }),
	{ description = "Resize vertically by 10", repeating = true }
)
hl.bind(
	config.main_mod .. " + CTRL + j",
	hl.dsp.window.resize({ x = 0, y = -10, relative = true }),
	{ description = "Resize horizontally by -10", repeating = true }
)
hl.bind(
	config.main_mod .. " + CTRL + k",
	hl.dsp.window.resize({ x = 0, y = 10, relative = true }),
	{ description = "Resize horizontally by 10", repeating = true }
)

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
hl.bind(
	config.main_mod .. " + PRINT",
	hl.dsp.exec_cmd(",hyprshot.sh --window"),
	{ description = "Screenshot current window", submap_universal = true }
)
hl.bind(
	"PRINT",
	hl.dsp.exec_cmd(",hyprshot.sh --output"),
	{ description = "Screenshot current output", submap_universal = true }
)
hl.bind(
	config.main_mod .. " + SHIFT + PRINT",
	hl.dsp.exec_cmd(",hyprshot.sh --region"),
	{ description = "Screenshot a selected region", submap_universal = true }
)
hl.bind("ALT + p", hl.dsp.exec_cmd("hyprpicker -a -n"), { description = "Execute hyprpicker to extract hex code" })
hl.bind(
	config.main_mod .. " + ALT + l",
	hl.dsp.exec_cmd("hyprlock -c ~/.config/hypr-chezmoi/hyprlock.conf"),
	{ description = "Lock the screen" }
)
