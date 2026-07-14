local hypr_dir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr"
package.path = package.path .. ";" .. hypr_dir .. "/?.lua"

---@type Config
---@diagnostic disable-next-line: missing-fields
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
		package_manager_ui = "shelly-ui",
	},
	host_configs = {
		["quantum-laptop"] = {
			primary_monitor = "eDP-1",
			secondary_monitor = "HDMI-A-1",
			hyprlock_conf = os.getenv("HOME") .. "/.config/hypr/hyprlock-laptop.conf",
			kb_options = "caps:swapescape",
			-- workspace_specs use monitor = "primary" as a sentinel, resolved to
			-- primary_monitor by the post-build pass at the bottom of this file.
			workspaces = {
				workspace_specs = {
					{
						workspace = "1",
						persistent = true,
						default = true,
						default_name = "code",
						layout = "monocle",
						monitor = "primary",
					},
					{
						workspace = "2",
						persistent = true,
						default_name = "study",
						layout = "scrolling",
						monitor = "primary",
					},
					{
						workspace = "3",
						persistent = true,
						default_name = "proton",
						layout = "scrolling",
						monitor = "primary",
					},
					{
						workspace = "4",
						persistent = true,
						default_name = "media",
						layout = "scrolling",
						monitor = "primary",
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
						monitor = "primary",
					},
					{
						workspace = "special:comms",
						layout = "scrolling",
					},
					{
						workspace = "special:music",
						layout = "scrolling",
					},
					{
						workspace = "special:launcher",
						layout = "scrolling",
					},
					{
						workspace = "special:ankama",
						on_created_empty = "gamemoderun ankama-launcher",
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
			primary_monitor = "DP-1",
			secondary_monitor = "DP-2",
			hyprlock_conf = os.getenv("HOME") .. "/.config/hypr/hyprlock.conf",
			workspaces = {
				workspace_specs = {
					-- layout_opts overrides the global dwindle default_split_ratio
					-- (see hypr/layouts/dwindle.lua) per workspace: 1.25 on the
					-- widescreen primary, 1.0 on normal-aspect monitors.
					{
						workspace = "1",
						persistent = true,
						default = true,
						default_name = "code",
						monitor = "primary",
						layout = "dwindle",
						layout_opts = { ["dwindle:default_split_ratio"] = 1.25 },
					},
					{
						workspace = "2",
						persistent = true,
						default_name = "study",
						monitor = "primary",
						layout = "dwindle",
						layout_opts = { ["dwindle:default_split_ratio"] = 1.25 },
					},
					{
						workspace = "3",
						persistent = true,
						default_name = "proton",
						monitor = "primary",
						layout = "dwindle",
						layout_opts = { ["dwindle:default_split_ratio"] = 1.25 },
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
						monitor = "primary",
					},
					{
						workspace = "5",
						persistent = true,
						default_name = "media",
						monitor = "secondary",
						layout = "dwindle",
						layout_opts = { ["dwindle:default_split_ratio"] = 1.0 },
					},
					{
						workspace = "6",
						persistent = true,
						default_name = "misc",
						monitor = "secondary",
						layout = "dwindle",
						layout_opts = { ["dwindle:default_split_ratio"] = 1.0 },
					},
					{
						workspace = "special:comms",
						layout = "dwindle",
					},
					{
						workspace = "special:music",
						layout = "scrolling",
					},
					{
						workspace = "special:launcher",
						layout = "scrolling",
					},
					{
						workspace = "special:ankama",
						on_created_empty = "gamemoderun ankama-launcher",
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

_G.config.__index = _G.config

-- Resolve the current host once, so every consumer reads `config.host.*`
-- without ever computing the hostname itself.
_G.config.host = assert(_G.config.host_configs[require("hypr.lib.util").hostname()], "no host_config for this hostname")

-- Resolve the "primary"/"secondary" monitor sentinels in workspace_specs to the
-- host's monitors. Done as a post-build pass since a Lua table constructor
-- cannot reference its own fields while being built.
local monitor_aliases = {
	primary = _G.config.host.primary_monitor,
	secondary = _G.config.host.secondary_monitor,
}
for _, spec in ipairs(_G.config.host.workspaces.workspace_specs) do
	if spec.monitor == "primary" or spec.monitor == "secondary" then
		spec.monitor = assert(
			monitor_aliases[spec.monitor],
			"workspace " .. tostring(spec.workspace) .. " uses '" .. spec.monitor .. "' but host has no such monitor"
		)
	end
end

require("hypr")
