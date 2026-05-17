local theme = require("conf.themes.macchiato")

hl.config({
	general = {
		col = {
			active_border = theme.mauve,
			inactive_border = theme.base,
		},
	},
	group = {
		col = {
			border_active = theme.mauve,
			border_inactive = theme.base,
			border_locked_active = theme.red,
			border_locked_inactive = theme.base,
		},
		groupbar = {
			col = {
				active = theme.mauve,
				inactive = theme.base,
				locked_active = theme.red,
				locked_inactive = theme.base,
			},
		},
	},
})
