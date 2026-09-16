-- Which palette the desk is on lives in the theme store, not here. hyprctl
-- cannot set these: `hyprctl keyword general:col.active_border` answers
-- "unknown request" on a Lua-configured Hyprland and still exits 0, so the
-- fan-out script could not push a colour and could not tell that it had failed.
-- A reload re-runs this file instead, which is why ,theme.sh reloads.
--
-- The accent colour is mode-scoped: every focus mode declares an
-- `accent_role` in its `presentation` block, and this file resolves it at
-- config load so the compositor's borders and groupbar match the mode's
-- identity. The palette itself (macchiato/latte) is selected by the sun
-- timer or the user; the accent_role names a role *within* that palette.
-- Falling back to mauve when the mode has no accent or the role is unknown
-- keeps the desk legible even during the first load before any mode is set.
local Store = require("hypr.lib.store")

local PALETTES = { latte = true, frappe = true, macchiato = true, mocha = true }

local name = Store.define("theme"):get("palette")
if not PALETTES[name] then
  name = "macchiato"
end

local theme = require("hypr.themes." .. name)

-- Resolve the mode-scoped accent. Two stores, each read once: the focus
-- pointer names the active mode (or "neutral" at rest), and the declaration
-- carries its `presentation.accent_role`. A missing or malformed entry
-- silently falls back to the palette's own mauve, so a fresh desk or a
-- declaration that has not yet been edited is never broken.
local function resolve_accent()
  local focus = Store.define("focus")
  local mode = focus:get("mode") or "neutral"
  local decl = Store.define("hyprfocus")
  local role = decl:get("modes", mode, "presentation", "accent_role")
  if role and type(theme[role]) == "string" then
    return theme[role]
  end
  return theme.mauve
end

local accent = resolve_accent()

hl.config({
  general = {
    col = {
      active_border = accent,
      inactive_border = theme.base,
    },
  },
  group = {
    col = {
      border_active = accent,
      border_inactive = theme.base,
      border_locked_active = theme.red,
      border_locked_inactive = theme.base,
    },
    groupbar = {
      col = {
        active = accent,
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
