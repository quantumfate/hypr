local hypr_dir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr"
package.path = package.path .. ";" .. hypr_dir .. "/?.lua"

---@type Config
_G.config = {
	main_mod = "SUPER",
	primary_mod = "CTRL",
	secondary_mod = "SHIFT",
	tertiary_mod = "ALT",
	app_cmds = {
		media_browser = "zen-twilight -P Media --name zen-twilight-media",
		main_browser = "zen-twilight",
		dev_browser = "firefox-developer-edition",
		terminal = "kitty --class Kitty-Main",
		terminal_float = "kitty --class Kitty-float",
		tmux = "kitty --class Tmux-Main tms",
		volume_control = "kitty --class Kitty-Wiremix wiremix",
		file_manager = "kitty --class Kitty-Yazi yazi",
		password_manager = "proton-pass",
		mail = "proton-mail",
		calculator = "qalculate-qt",
		app_launcher = 'rofi -show drun -run-command "uwsm app -- {cmd}"',
	},
	hyprlock_conf = os.getenv("HOME")
		.. (
			require("hypr.lib.util").hostname() == "quantum-desktop" and "/.config/hypr/hyprlock.conf"
			or "/.config/hypr/hyprlock-laptop.conf"
		),
	host_configs = {
		["quantum-laptop"] = {
			workspaces = {
				workspace_specs = {
					{
						workspace = "1",
						persistent = true,
						default = true,
						default_name = "code",
						layout = "monocle",
						monitor = "eDP-1",
					},
					{
						workspace = "2",
						persistent = true,
						default_name = "study",
						layout = "scrolling",
						monitor = "eDP-1",
					},
					{
						workspace = "3",
						persistent = true,
						default_name = "proton",
						layout = "scrolling",
						monitor = "eDP-1",
					},
					{
						workspace = "4",
						persistent = true,
						default_name = "media",
						layout = "scrolling",
						monitor = "eDP-1",
					},
					{
						workspace = "5",
						persistent = true,
						gaps_in = 0,
						gaps_out = 0,
						border_size = 0,
						decorate = false,
						layout = "monocle",
						default_name = "gaming",
						monitor = "eDP-1",
					},
					{
						workspace = "special:comms",
						layout = "scrolling",
					},
					{
						workspace = "special:music",
						layout = "scrolling",
					},
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
		},
		["quantum-desktop"] = {
			workspaces = {
				workspace_specs = {
					{
						workspace = "1",
						persistent = true,
						default = true,
						default_name = "code",
						monitor = "DP-1",
						layout = "master",
					},
					{ workspace = "2", persistent = true, default_name = "study", monitor = "DP-1", layout = "master" },
					{
						workspace = "3",
						persistent = true,
						default_name = "proton",
						monitor = "DP-1",
						layout = "dwindle",
					},
					{
						workspace = "4",
						persistent = true,
						gaps_in = 0,
						gaps_out = 0,
						border_size = 0,
						decorate = false,
						default_name = "gaming",
						layout = "monocle",
						monitor = "DP-1",
					},
					{
						workspace = "5",
						persistent = true,
						default_name = "media",
						monitor = "DP-2",
						layout = "scrolling",
					},
					{
						workspace = "special:comms",
						layout = "scrolling",
					},
					{
						workspace = "special:music",
						layout = "scrolling",
					},
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
		},
	},
}

require("hypr")
