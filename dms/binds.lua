-- Keybinds (ported from dms/binds.conf).
--
-- Flag mapping from the old hyprlang bind variants:
--   bindl   -> { locked = true }
--   bindel  -> { locked = true, repeating = true }
--   bindd   -> { description = "..." }
--   binddu  -> { description = "...", submap_universal = true }
--   binddum -> { description = "...", submap_universal = true, mouse = true }
--   bindde  -> { description = "...", repeating = true }

local mainMod = "SUPER"
local browser = "zen-twilight"
local terminal = "kitty"
local shared_scripts = "~/.local/share/own-scripts/github/quantumfate/scripts"
local hyprland_scripts = "~/.config/hypr/scripts"

-- === Application launchers ===
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd("dms ipc call spotlight toggle"))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("dms ipc call clipboard toggle"))
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("dms ipc call processlist focusOrToggle"))
hl.bind(mainMod .. " + comma", hl.dsp.exec_cmd("dms ipc call settings focusOrToggle"))
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("dms ipc call notifications toggle"))
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd("dms ipc call notepad toggle"))
hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("dms ipc call powermenu toggle"))

-- === Cheat sheet ===
hl.bind(mainMod .. " + SHIFT + Slash", hl.dsp.exec_cmd("dms ipc call keybinds toggle hyprland"))

-- === Security ===
hl.bind(mainMod .. " + ALT + L", hl.dsp.exec_cmd("dms ipc call lock lock"))
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd("dms ipc call processlist focusOrToggle"))

-- === Audio controls ===
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("dms ipc call audio increment 3"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("dms ipc call audio decrement 3"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("dms ipc call audio mute"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("dms ipc call audio micmute"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("dms ipc call mpris playPause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("dms ipc call mpris playPause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("dms ipc call mpris previous"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("dms ipc call mpris next"), { locked = true })
hl.bind(
	"CTRL + XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("dms ipc call mpris increment 3"),
	{ locked = true, repeating = true }
)
hl.bind(
	"CTRL + XF86AudioLowerVolume",
	hl.dsp.exec_cmd("dms ipc call mpris decrement 3"),
	{ locked = true, repeating = true }
)

-- === Brightness controls ===
hl.bind(
	"XF86MonBrightnessUp",
	hl.dsp.exec_cmd('dms ipc call brightness increment 5 ""'),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86MonBrightnessDown",
	hl.dsp.exec_cmd('dms ipc call brightness decrement 5 ""'),
	{ locked = true, repeating = true }
)

-- === Window management ===
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.window.float())

-- === Terminal ===
hl.bind(
	mainMod .. " + return",
	hl.dsp.exec_cmd("uwsm app -- " .. terminal .. " --class Kitty-Main"),
	{ description = "Open the Terminal", submap_universal = true }
)
hl.bind(
	mainMod .. " + s",
	hl.dsp.exec_cmd("uwsm app -- " .. terminal .. " --class Tmux-Main tms"),
	{ description = "Open Kitty with Tmux Session", submap_universal = true }
)
hl.bind(
	mainMod .. " + SHIFT + return",
	hl.dsp.exec_cmd("uwsm app -- " .. terminal .. " --class Kitty-float"),
	{ description = "Open the Terminal", submap_universal = true }
)
hl.bind(
	mainMod .. " + ALT + d",
	hl.dsp.exec_cmd("uwsm-app -- zen-twilight -P Media --name zen-twilight-media --no-remote"),
	{ description = "Open Zen Browser media profile", submap_universal = true }
)

-- === Applications ===
hl.bind(
	mainMod .. " + semicolon",
	hl.dsp.exec_cmd(shared_scripts .. "/wrapper/minimize.sh"),
	{ description = "Close focused window", submap_universal = true }
)
hl.bind(
	mainMod .. " + b",
	hl.dsp.exec_cmd("uwsm app -- " .. browser),
	{ description = "Open the Browser", submap_universal = true }
)
hl.bind(
	mainMod .. " + c",
	hl.dsp.exec_cmd("uwsm app -- qalculate-qt"),
	{ description = "Open Calculator", submap_universal = true }
)
hl.bind(
	mainMod .. " + m",
	hl.dsp.exec_cmd("uwsm app -- proton-pass"),
	{ description = "Open Proton Pass", submap_universal = true }
)
hl.bind(
	mainMod .. " + r",
	hl.dsp.exec_cmd('rofi -show drun -run-command "uwsm app -- {cmd}"'),
	{ description = "Open Application Launcher", submap_universal = true }
)

-- === Special workspaces ===
hl.bind(
	mainMod .. " + ALT + s",
	hl.dsp.workspace.toggle_special("spotify"),
	{ description = "Toggle Special Workspace spotify", submap_universal = true }
)
hl.bind(
	mainMod .. " + ALT + v",
	hl.dsp.workspace.toggle_special("vesktop"),
	{ description = "Toggle Special Workspace vesktop", submap_universal = true }
)

-- === Workspaces ===
hl.bind(
	mainMod .. " + TAB",
	hl.dsp.focus({ workspace = "e-1" }),
	{ description = "Previous workspace", submap_universal = true }
)
hl.bind(
	mainMod .. " + SHIFT + TAB",
	hl.dsp.focus({ workspace = "e+1" }),
	{ description = "Next workspace", submap_universal = true }
)

-- dvorak-custom number row: keys map to workspaces 1-10 in order.
local wsKeys = {
	"plus",
	"bracketleft",
	"braceleft",
	"parenleft",
	"ampersand",
	"equal",
	"parenright",
	"braceright",
	"bracketright",
	"asterisk",
}
for i, key in ipairs(wsKeys) do
	hl.bind(
		mainMod .. " + " .. key,
		hl.dsp.focus({ workspace = i }),
		{ description = "Switch to workspace " .. i, submap_universal = true }
	)
end
for i, key in ipairs(wsKeys) do
	hl.bind(
		mainMod .. " + SHIFT + " .. key,
		hl.dsp.window.move({ workspace = i, follow = true }),
		{ description = "Move focused to workspace " .. i, submap_universal = true }
	)
end

-- === Window focus / swap / resize ===
hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "l" }), { description = "Move window focus to the left" })
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "r" }), { description = "Move window focus to the right" })
hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "u" }), { description = "Move window focus up" })
hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "d" }), { description = "Move window focus down" })

hl.bind(
	mainMod .. " + SHIFT + h",
	hl.dsp.window.swap({ direction = "l" }),
	{ description = "Swap current window with the window to the left" }
)
hl.bind(
	mainMod .. " + SHIFT + l",
	hl.dsp.window.swap({ direction = "r" }),
	{ description = "Swap current window with the window to the right" }
)
hl.bind(
	mainMod .. " + SHIFT + j",
	hl.dsp.window.swap({ direction = "u" }),
	{ description = "Swap current window with the lower window" }
)
hl.bind(
	mainMod .. " + SHIFT + k",
	hl.dsp.window.swap({ direction = "d" }),
	{ description = "Swap current window with the upper window" }
)

hl.bind(
	mainMod .. " + CTRL + h",
	hl.dsp.window.resize({ x = -10, y = 0, relative = true }),
	{ description = "Resize vertical by -10", repeating = true }
)
hl.bind(
	mainMod .. " + CTRL + l",
	hl.dsp.window.resize({ x = 10, y = 0, relative = true }),
	{ description = "Resize vertically by 10", repeating = true }
)
hl.bind(
	mainMod .. " + CTRL + j",
	hl.dsp.window.resize({ x = 0, y = -10, relative = true }),
	{ description = "Resize horizontally by -10", repeating = true }
)
hl.bind(
	mainMod .. " + CTRL + k",
	hl.dsp.window.resize({ x = 0, y = 10, relative = true }),
	{ description = "Resize horizontally by 10", repeating = true }
)

-- === Mouse bindings ===
hl.bind(
	mainMod .. " + ALT + mouse:272",
	hl.dsp.window.drag(),
	{ description = "Move a window with left click", submap_universal = true, mouse = true }
)
hl.bind(
	mainMod .. " + ALT + mouse:273",
	hl.dsp.window.resize(),
	{ description = "Resize a window with right click", submap_universal = true, mouse = true }
)
hl.bind(
	mainMod .. " + ALT + m",
	hl.dsp.exec_cmd(hyprland_scripts .. "/minimize.sh --toggle"),
	{ description = "Minimize Window", submap_universal = true }
)

-- === Utility ===
hl.bind(
	mainMod .. " + PRINT",
	hl.dsp.exec_cmd(shared_scripts .. "/wrapper/hyprshot.sh --window"),
	{ description = "Screenshot current window", submap_universal = true }
)
hl.bind(
	"PRINT",
	hl.dsp.exec_cmd(shared_scripts .. "/wrapper/hyprshot.sh --output"),
	{ description = "Screenshot current output", submap_universal = true }
)
hl.bind(
	mainMod .. " + SHIFT + PRINT",
	hl.dsp.exec_cmd(shared_scripts .. "/wrapper/hyprshot.sh --region"),
	{ description = "Screenshot a selected region", submap_universal = true }
)
hl.bind("ALT + p", hl.dsp.exec_cmd("hyprpicker -a -n"), { description = "Execute hyprpicker to extract hex code" })
hl.bind(
	mainMod .. " + ALT + l",
	hl.dsp.exec_cmd("hyprlock -c ~/.config/hypr-chezmoi/hyprlock.conf"),
	{ description = "Lock the screen" }
)
