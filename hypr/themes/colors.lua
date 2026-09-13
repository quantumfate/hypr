local theme = require("hypr.themes.macchiato")

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
      -- The title has to read against both of those grounds, so it is not one
      -- colour: crust on the accent, text on the base.
      text_color = theme.crust,
      text_color_inactive = theme.text,
      text_color_locked_active = theme.crust,
      text_color_locked_inactive = theme.text,
    },
  },
})
