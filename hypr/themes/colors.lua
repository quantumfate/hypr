-- Which palette the desk is on lives in the theme store, not here. hyprctl
-- cannot set these: `hyprctl keyword general:col.active_border` answers
-- "unknown request" on a Lua-configured Hyprland and still exits 0, so the
-- fan-out script could not push a colour and could not tell that it had failed.
-- A reload re-runs this file instead, which is why ,theme.sh reloads.
local Store = require("hypr.lib.store")

local PALETTES = { latte = true, frappe = true, macchiato = true, mocha = true }

local name = Store.define("theme"):get("palette")
if not PALETTES[name] then
  name = "macchiato"
end

local theme = require("hypr.themes." .. name)

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
