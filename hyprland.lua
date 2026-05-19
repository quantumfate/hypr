local hypr_dir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr"
package.path = package.path .. ";" .. hypr_dir .. "/?.lua"

local mt = require("hypr.lib.mt")

---@type Config
_G.config = {
	main_mod = "SUPER",
	app_cmds = {
		media_browser = "zen-twilight -P media --name zen-twilight-media",
		main_browser = "zen-twilight -P default --name zen-twilight-main",
		terminal = "kitty --class Kitty-Main",
		terminal_float = "kitty --class Kitty-float",
		tmux = "kitty --class Tmux-Main tms",
		password_manager = "proton-pass",
		mail = "proton-mail",
		calculator = "qalculate-qt",
		app_launcher = 'rofi -show drun -run-command "uwsm app -- {cmd}"',
	},
	workspaces = {
		workspace_specs = {
			{
				workspace = "1",
				persistent = true,
				default = true,
				default_name = "code",
			},
			{ workspace = "2", persistent = true, default_name = "study" },
			{ workspace = "3", persistent = true, default_name = "mail" },
			{ workspace = "4", persistent = true, default_name = "media" },
			{
				workspace = "5",
				persistent = true,
				gaps_in = 0,
				gaps_out = 0,
				border_size = 0,
				decorate = false,
				default_name = "gaming",
			},
			{ workspace = "6", persistent = true, default_name = "media" },
		},
		workspace_keys = {
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
		},
	},
	host_configs = {
		["quantum-laptop"] = {
			monitors = mt.reverse_index_lookup_by_key({
				["eDP-1"] = {
					workspaces = { 1, 2, 3, 4, 5, 6 },
					layouts = mt.reverse_index_lookup({
						scrolling = { 1, 2, 3, 4, 6 },
						monocle = { 5 },
					}),
				},
			}, "workspaces"),
		},
		["quantum-desktop"] = {
			monitors = mt.reverse_index_lookup_by_key({
				["DP-1"] = {
					workspaces = { 1, 2, 3, 4, 5 },
					layouts = mt.reverse_index_lookup({
						master = { 1, 2, 3, 4 },
						monocle = { 5 },
					}),
				},
				["DP-2"] = {
					workspaces = { 6 },
					layouts = mt.reverse_index_lookup({
						dwindle = { 6 },
					}),
				},
			}, "workspaces"),
		},
	},
}

require("hypr")
