local hypr_dir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr"
package.path = package.path .. ";" .. hypr_dir .. "/?.lua"

require("conf")

hl.config({
	cursor = {
		no_warps = true,
	},

	decoration = {
		rounding = 4,
		active_opacity = 0.92,
		inactive_opacity = 0.85,
		dim_around = 0.6,
		dim_special = 0.4,

		blur = {
			enabled = true,
			size = 6, -- blur kernel radius
			passes = 3, -- 2 = cheap, 3 = sweet spot, 4+ = diminishing returns
			new_optimizations = true,
			xray = false, -- true = blur sees through ALL windows to wallpaper
			ignore_opacity = true, -- blur even fully-opaque regions of windows below
			noise = 0.02, -- subtle film grain hides banding
			contrast = 1.05, -- slightly punch up blurred content
			brightness = 1.0,
			vibrancy = 0.18, -- saturation boost on blurred areas
			vibrancy_darkness = 0.0,
			popups = true, -- blur menus/tooltips too
			popups_ignorealpha = 0.2,
		},

		shadow = {
			enabled = true,
			range = 30,
			render_power = 5,
			offset = { 0, 5 },
			color = "rgba(00000070)",
		},
	},

	general = {
		border_size = 2,
		gaps_in = 2,
		gaps_out = 5,
		float_gaps = -1,
		layout = "master",
		allow_tearing = false,
		resize_on_border = false,
		no_focus_fallback = true,

		snap = {
			enabled = true,
			monitor_gap = 30,
			border_overlap = false,
		},
	},

	group = {
		auto_group = true,
		groupbar = {
			enabled = true,
		},
	},

	input = {
		kb_layout = "dvorak-custom",
		follow_mouse = 0,
		mouse_refocus = false,
		sensitivity = 0.2,
		touchpad = {
			disable_while_typing = true,
		},
	},

	master = {
		new_status = "inherit",
		orientation = "left",
		new_on_active = "after",
		mfact = 0.70,
		center_master_fallback = "right",
		always_keep_position = false,
		slave_count_for_center_master = 2,
	},

	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		focus_on_activate = true,
		font_family = "Hack Nerd Font Mono",
		size_limits_tiled = true,
		mouse_move_enables_dpms = true,
	},
})

hl.layer_rule({ match = { namespace = "notifications" }, animation = "slide" })

hl.layer_rule({ match = { namespace = "^(quickshell)$" }, no_anim = true })
