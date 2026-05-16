-- Window rules (ported from conf/windowrules.conf).
-- Rules are evaluated top-to-bottom; the last match wins for a given window.

-- Browser
hl.window_rule({ match = { initial_class = "([fF]irefox|zen|zen-twilight|zen-beta)" }, tag = "+default-browser" })
hl.window_rule({ match = { initial_class = "(zen-twilight-media)" }, tag = "+media-browser" })

-- App categories
hl.window_rule({ match = { class = "(Alacritty|kitty|ghostty|foot)" }, tag = "+terminal" })
hl.window_rule({ match = { title = "(Picture.?in.?[Pp]icture)" }, tag = "+pip" })
hl.window_rule({ match = { initial_title = "Discord Popout" }, tag = "+pip" })

-- Floating windows
hl.window_rule({
	match = {
		initial_class = [[(protonvpn-app|Impala|About|Wiremix|com.gabm.satty|Calos|TUI.float|io\.github\.Qalculate\.qalculate-qt|Proton Pass)]],
	},
	tag = "+floating-window",
})
hl.window_rule({
	match = { initial_class = "(Ranger-tui|Wiremix-tui|Btop-tui|Parui-tui|Blue-tui)" },
	tag = "+floating-window",
})
hl.window_rule({
	match = {
		initial_class = "(xdg-desktop-portal-hyprland|xdg-desktop-portal-gtk|sublime_text|DesktopEditors)",
		title = "(Open.*Files?|Save.*Files?|Save.*As|All Files|Save)",
	},
	tag = "+floating-window",
})
hl.window_rule({
	match = { initial_class = "(zen|zen-twilight|zen-beta)", title = "(Library)" },
	tag = "+floating-window",
})
hl.window_rule({
	match = { initial_class = "(zen|zen-twilight|zen-beta)", title = "Add bookmark folder" },
	tag = "+floating-window",
})
hl.window_rule({
	match = { initial_class = [[(org\.keepassxc\.KeePassXC)]], title = "(Unlock Database - KeePassXC)" },
	tag = "+floating-window",
})
hl.window_rule({ match = { initial_class = "(wdisplays)" }, tag = "+floating-window" })

-- Windows excluded from screen share
hl.window_rule({ match = { initial_class = "(Proton Pass|Proton Mail)" }, tag = "+exclude-from-screenshare" })

-- Workspaces
hl.window_rule({ match = { class = "(Kitty-Main|Tmux-Main)" }, workspace = "1" })
hl.window_rule({ match = { initial_class = "zen-twilight" }, workspace = "1" })
hl.window_rule({ match = { class = "(obsidian)" }, workspace = "2" })
hl.window_rule({ match = { class = "(Proton Mail)" }, workspace = "3" })

hl.window_rule({ match = { class = [[steam_app_\d+]] }, workspace = "5", fullscreen_state = "2 2" })
hl.window_rule({
	match = { class = "(steam)" },
	workspace = "5",
	suppress_event = "activatefocus",
})
hl.window_rule({ match = { class = "(steam)" }, workspace = "5", suppress_event = "activate" })
hl.window_rule({ match = { class = "(steam)", title = "Friends List" }, workspace = "5", move = { 300, 400 } })
hl.window_rule({ match = { class = "(steam)", title = "Launching..." }, workspace = "5", move = { 600, 600 } })

hl.window_rule({ match = { tag = "media-browser" }, workspace = "6" })

-- Picture in Picture (tag: pip)
hl.window_rule({ match = { tag = "pip" }, float = true })
hl.window_rule({ match = { tag = "pip" }, pin = true })
hl.window_rule({ match = { tag = "pip" }, size = { 600, 338 } })
hl.window_rule({ match = { tag = "pip" }, keep_aspect_ratio = true })
hl.window_rule({ match = { tag = "pip" }, border_size = 0 })
hl.window_rule({ match = { tag = "pip" }, opacity = "1 override 1 override" })
-- original `move 100%-w-40 4%` -> monitor-local expression form
hl.window_rule({ match = { tag = "pip" }, move = { "monitor_w - window_w - 40", "monitor_h * 0.04" } })

-- Floating windows (tag: floating-window)
hl.window_rule({ match = { tag = "floating-window" }, float = true })
hl.window_rule({ match = { tag = "floating-window" }, center = true })
hl.window_rule({ match = { tag = "floating-window" }, max_size = { 1400, 1000 } })
hl.window_rule({ match = { tag = "floating-window" }, persistent_size = true })
hl.window_rule({ match = { tag = "floating-window" }, fullscreen_state = "0 0" })

-- One-off floats
hl.window_rule({ match = { class = "(ffplay|clipse|Kitty-float)" }, float = true })
hl.window_rule({ match = { tag = "floating-window" }, persistent_size = true })
hl.window_rule({ match = { class = "(clipse)" }, size = { 800, 600 } })
hl.window_rule({ match = { class = "(Kitty-float)" }, size = { 640, 360 } })
hl.window_rule({ match = { class = "(Kitty-float)" }, center = true })

-- Steam floats
hl.window_rule({ match = { title = "(Steam Settings|Friends List)" }, float = true })

-- Tiling overrides
hl.window_rule({ match = { tag = "chromium-based-browser" }, tile = true })

-- Focus / behaviour
hl.window_rule({ match = { class = "(vesktop|whatsapp-electron)" }, suppress_event = "activatefocus" })
hl.window_rule({ match = { class = "(vesktop|whatsapp-electron)" }, suppress_event = "activate" })

-- Exclude from screenshare
hl.window_rule({ match = { tag = "exclude-from-screenshare" }, no_screen_share = true })

-- Opacity
hl.window_rule({
	match = {
		class = "^(zoom|vlc|mpv|mp4|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$",
	},
	opacity = "1 1",
})

hl.window_rule({ match = { class = [[^(org\.wezfurlong\.wezterm)$]] }, tile = true })

hl.window_rule({ match = { class = [[^(org\.gnome\.)]] }, rounding = 12 })

hl.window_rule({ match = { class = "^(gnome-control-center)$" }, tile = true })
hl.window_rule({ match = { class = "^(pavucontrol)$" }, tile = true })
hl.window_rule({ match = { class = "^(nm-connection-editor)$" }, tile = true })

hl.window_rule({ match = { class = [[^(org\.gnome\.Calculator)$]] }, float = true })
hl.window_rule({ match = { class = "^(gnome-calculator)$" }, float = true })
hl.window_rule({ match = { class = "^(galculator)$" }, float = true })
hl.window_rule({ match = { class = "^(blueman-manager)$" }, float = true })
hl.window_rule({ match = { class = [[^(org\.gnome\.Nautilus)$]] }, float = true })
hl.window_rule({ match = { class = "^(xdg-desktop-portal)$" }, float = true })

hl.window_rule({ match = { class = "^(steam)$", title = "^(notificationtoasts)" }, no_initial_focus = true })
hl.window_rule({ match = { class = "^(steam)$", title = "^(notificationtoasts)" }, pin = true })

hl.window_rule({ match = { class = "^(firefox)$", title = "^(Picture-in-Picture)$" }, float = true })
hl.window_rule({ match = { class = "^(zoom)$" }, float = true })

-- Named window rules (ported from conf/misc/named-windowrules.conf).
-- Named rules can be toggled at runtime and are evaluated before anonymous ones.

hl.window_rule({
	name = "feh",
	match = { initial_class = "feh" },
	workspace = "special:feh",
	float = true,
	content = "photo",
	center = true,
	rounding = 0,
	opacity = "1 override 1 override",
})

hl.window_rule({
	name = "workspace-spotify",
	match = { initial_class = "([Ss]potify)" },
	workspace = "special:spotify",
})

hl.window_rule({
	name = "workspace-vesktop",
	match = { initial_class = "vesktop" },
	workspace = "special:vesktop",
})
