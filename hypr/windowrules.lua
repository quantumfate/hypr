local windowrule = require("hypr.lib.windowrule")

windowrule.tag_props({
	{ initial_class = "([fF]irefox|zen|zen-twilight|zen-beta)" },
}, "+default-browser")

windowrule.tag_props({
	{ initial_class = "(zen-twilight-media)" },
}, "+media-browser")

windowrule.tag_props({
	{ tag = "default-browser" },
	{ initial_class = "(Kitty-Main|Tmux-Main)" },
	{ initial_class = "(firefox-developer-edition)" },
}, "+code")

windowrule.tag_set_effects("code", {
	static = { workspace = "name:code" },
})

windowrule.tag_props({
	{ initial_class = "(obsidian)" },
}, "study")

windowrule.tag_set_effects("study", {
	static = { workspace = "name:study" },
})

windowrule.tag_props({
	{ initial_class = "(Proton Mail)" },
	{ initial_class = "(Proton Pass)" },
}, "proton")

windowrule.tag_set_effects("proton", {
	static = { workspace = "name:proton" },
})

windowrule.tag_props({
	{ initial_class = "(Alacritty|kitty|ghostty|foot)" },
}, "+terminal")

windowrule.tag_props({
	{ initial_title = "(Picture.?in.?[Pp]icture)" },
	{ tag = "media-browser", title = "^(Picture-in-Picture)$" },
	{ tag = "default-browser", title = "^(Picture-in-Picture)$" },
}, "+pip")

windowrule.tag_set_effects("pip", {
	static = {
		float = true,
		size = { "window_w * 0.2", "monitor_h * 0.2" },
		keep_aspect_ratio = true,
		border_size = 0,
	},
	dynamic = {
		opacity = "1 override 1 override",
		move = { "window_w * 0.7", "monitor_h * 0.7" },
	},
})

windowrule.tag_props({
	{
		initial_class = [[(protonvpn-app|Impala|About|Wiremix|com.gabm.satty|Calos|TUI.float|io\.github\.Qalculate\.qalculate-qt)]],
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
}, "+floating-window")

windowrule.tag_set_effects("floating-window", {
	static = { float = true, center = true, fullscreen_state = "0 0" },
	dynamic = { max_size = { "monitor_w * 0.7", "monitor_h * 0.7" }, persistent_size = true },
})

windowrule.tag_props({
	{ initial_class = "(Proton Pass|Proton Mail)" },
}, "+exclude-from-screenshare")

windowrule.tag_set_effects("exclude-from-screenshare", {
	dynamic = { no_screen_share = true },
})

windowrule.tag_set_effects("media-browser", {
	static = { workspace = "name:media" },
})

-- Gaming
windowrule.tag_props({
	{ class = [[steam_app_\d+]] },
	{ class = "(steam)" },
	{ class = "steam_app_default", title = "Zenimax Online Studios Launcher" },
	{ class = "steam_app_default" },
}, "+gaming")

windowrule.tag_set_effects("gaming", {
	static = { workspace = "name:gaming", suppress_event = "activate activatefocus", fullscreen_state = "2 1" },
})

windowrule.tag_props({
	{ class = "(steam)" },
	{ class = "steam_app_default", title = "Zenimax Online Studios Launcher" },
	{ class = "net.lutris.Lutris" },
}, "+launcher")

windowrule.tag_set_effects("launcher", {
	static = { workspace = "special:launcher" },
})

hl.window_rule({ match = { class = [[steam_app_\d+]] }, fullscreen_state = "2 2" })
hl.window_rule({ match = { class = "(steam)", title = "Friends List" }, move = { 300, 400 }, float = true })
hl.window_rule({ match = { class = "(steam)", title = "Launching..." }, move = { 600, 600 } })
hl.window_rule({ match = { title = "(Steam Settings)" }, float = true })

-- Steam notification toasts
windowrule.tag_props({
	{ class = "^(steam)$", title = "^(notificationtoasts)" },
}, "+steam-toast")

windowrule.tag_set_effects("steam-toast", {
	static = { no_initial_focus = true, pin = true },
})

-- Comms
windowrule.tag_props({
	{ class = "(vesktop|whatsapp-electron|signal)" },
}, "+comms")

windowrule.tag_set_effects("comms", {
	static = { suppress_event = "activate activatefocus", workspace = "special:comms" },
})

-- Media apps (opacity fix)
windowrule.tag_props({
	{
		class = "^(zoom|vlc|mpv|mp4|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$",
	},
}, "+media-app")

windowrule.tag_set_effects("media-app", {
	dynamic = { opacity = "1 1" },
})

-- Tile overrides
windowrule.tag_props({
	{ class = [[^(org\.wezfurlong\.wezterm)$]] },
	{ class = "^(gnome-control-center)$" },
	{ class = "^(pavucontrol)$" },
	{ class = "^(nm-connection-editor)$" },
	{ tag = "chromium-based-browser" },
}, "+tile-override")

windowrule.tag_set_effects("tile-override", {
	static = { tile = true },
})

-- Float overrides
windowrule.tag_props({
	{ class = [[^(org\.gnome\.Calculator)$]] },
	{ class = "^(gnome-calculator|galculator|blueman-manager|zoom|xdg-desktop-portal)$" },
	{ class = [[^(org\.gnome\.Nautilus)$]] },
	{ class = "(ffplay|clipse|Kitty-float)" },
	{ tag = "launcher" },
}, "+float-override")

windowrule.tag_set_effects("float-override", {
	static = { float = true },
})

hl.window_rule({ match = { class = "(clipse)" }, size = { 800, 600 } })
hl.window_rule({ match = { class = "(Kitty-float)" }, size = { 1000, 800 }, center = true })

-- Gnome rounding
windowrule.tag_props({
	{ class = [[^(org\.gnome\.)]] },
}, "+gnome-app")

windowrule.tag_set_effects("gnome-app", {
	dynamic = { rounding = 12 },
})

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

windowrule.tag_props({ { initial_class = "([Ss]potify)" } }, "+music")
windowrule.tag_set_effects("music", { static = { workspace = "special:music" } })
