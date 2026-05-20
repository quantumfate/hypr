---@type WindowRuleConfig
local M = {
	tag_scopes = {
		default_browser = {
			tag = "+default-browser",
			matches = {
				{ initial_class = "([fF]irefox|zen|zen-twilight|zen-beta)" },
			},
		},
		terminal = {
			tag = "+terminal",
			matches = {
				{ class = "(Alacritty|kitty|ghostty|foot)" },
			},
		},
		pip = {
			tag = "+pip",
			matches = {
				{ title = "(Picture.?in.?[Pp]icture)" },
				{ initial_title = "Discord Popout" },
			},
			props = {
				float = true,
				pin = true,
				size = { 600, 338 },
				keep_aspect_ratio = true,
				border_size = 0,
				opacity = "1 override 1 override",
				move = { "monitor_w - window_w - 40", "monitor_h * 0.04" },
			},
		},
		floating_window = {
			tag = "+floating-window",
			matches = {
				{
					initial_class = [[(protonvpn-app|Impala|About|Wiremix|com.gabm.satty|Calos|TUI.float|io\.github\.Qalculate\.qalculate-qt|Proton Pass)]],
				},
				{ initial_class = "(Ranger-tui|Wiremix-tui|Btop-tui|Parui-tui|Blue-tui)" },
				{
					initial_class = "(xdg-desktop-portal-hyprland|xdg-desktop-portal-gtk|sublime_text|DesktopEditors)",
					title = "(Open.*Files?|Save.*Files?|Save.*As|All Files|Save)",
				},
				{ initial_class = "(zen|zen-twilight|zen-beta)", title = "(Library)" },
				{ initial_class = "(zen|zen-twilight|zen-beta)", title = "Add bookmark folder" },
				{ initial_class = [[(org\.keepassxc\.KeePassXC)]], title = "(Unlock Database - KeePassXC)" },
				{ initial_class = "(wdisplays)" },
			},
			props = {
				float = true,
				center = true,
				max_size = { 1400, 1000 },
				persistent_size = true,
				fullscreen_state = "0 0",
			},
		},
		exclude_from_screenshare = {
			tag = "+exclude-from-screenshare",
			matches = {
				{ initial_class = "(Proton Pass|Proton Mail)" },
			},
			props = { no_screen_share = true },
		},
	},

	workspace_assigns = {
		["name:code"] = {
			{ match = { class = "(Kitty-Main|Tmux-Main)" } },
			{ match = { initial_class = "zen-twilight" } },
			{ match = { initial_class = "([fF]irefox|zen|zen-twilight|zen-beta)" } },
		},
		["name:study"] = {
			{ match = { class = "(obsidian)" } },
		},
		["name:mail"] = {
			{ match = { class = "(Proton Mail)" } },
		},
		["name:media"] = {
			{ match = { initial_class = "(zen-twilight-media)" } },
		},
		["name:gaming"] = {
			{ match = { class = [[steam_app_\d+]] }, props = { fullscreen_state = "2 2" } },
			{ match = { class = "(steam)" }, props = { suppress_event = "activatefocus" } },
			{ match = { class = "(steam)" }, props = { suppress_event = "activate" } },
			{ match = { class = "(steam)", title = "Friends List" }, props = { move = { 300, 400 } } },
			{ match = { class = "(steam)", title = "Launching..." }, props = { move = { 600, 600 } } },
		},
	},

	rules = {
		-- One-off floats
		{ match = { class = "(ffplay|clipse|Kitty-float)" }, props = { float = true } },
		{ match = { class = "(clipse)" }, props = { size = { 800, 600 } } },
		{ match = { class = "(Kitty-float)" }, props = { size = { 640, 360 }, center = true } },

		-- Steam floats by title
		{ match = { title = "(Steam Settings|Friends List)" }, props = { float = true } },

		-- Tiling overrides
		{ match = { tag = "chromium-based-browser" }, props = { tile = true } },
		{ match = { class = [[^(org\.wezfurlong\.wezterm)$]] }, props = { tile = true } },
		{ match = { class = "^(gnome-control-center)$" }, props = { tile = true } },
		{ match = { class = "^(pavucontrol)$" }, props = { tile = true } },
		{ match = { class = "^(nm-connection-editor)$" }, props = { tile = true } },

		-- Focus / behaviour
		{ match = { class = "(vesktop|whatsapp-electron)" }, props = { suppress_event = "activatefocus" } },
		{ match = { class = "(vesktop|whatsapp-electron)" }, props = { suppress_event = "activate" } },

		-- Opacity
		{
			match = {
				class = "^(zoom|vlc|mpv|mp4|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$",
			},
			props = { opacity = "1 1" },
		},

		-- Rounding
		{ match = { class = [[^(org\.gnome\.)]] }, props = { rounding = 12 } },

		-- Floating apps
		{ match = { class = [[^(org\.gnome\.Calculator)$]] }, props = { float = true } },
		{ match = { class = "^(gnome-calculator)$" }, props = { float = true } },
		{ match = { class = "^(galculator)$" }, props = { float = true } },
		{ match = { class = "^(blueman-manager)$" }, props = { float = true } },
		{ match = { class = [[^(org\.gnome\.Nautilus)$]] }, props = { float = true } },
		{ match = { class = "^(xdg-desktop-portal)$" }, props = { float = true } },
		{ match = { class = "^(zoom)$" }, props = { float = true } },

		-- Steam notification toasts
		{
			match = { class = "^(steam)$", title = "^(notificationtoasts)" },
			props = { no_initial_focus = true, pin = true },
		},

		-- Firefox PiP
		{ match = { class = "^(firefox)$", title = "^(Picture-in-Picture)$" }, props = { float = true } },
	},

	named = {
		feh = {
			name = "feh",
			match = { initial_class = "feh" },
			props = {
				workspace = "special:feh",
				float = true,
				content = "photo",
				center = true,
				rounding = 0,
				opacity = "1 override 1 override",
			},
		},
		workspace_spotify = {
			name = "workspace-spotify",
			match = { initial_class = "([Ss]potify)" },
			props = { workspace = "special:spotify" },
		},
		workspace_vesktop = {
			name = "workspace-vesktop",
			match = { initial_class = "vesktop" },
			props = { workspace = "special:vesktop" },
		},
	},
}

return M
