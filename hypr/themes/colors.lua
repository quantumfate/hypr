-- Which palette the desk is on lives in the theme store, not here. hyprctl
-- cannot set these: `hyprctl keyword general:col.active_border` answers
-- "unknown request" on a Lua-configured Hyprland and still exits 0, so the
-- fan-out script could not push a colour and could not tell that it had failed.
-- A reload re-runs this file instead, which is why ,theme.sh reloads.
--
-- The accent colour is mode-scoped: every focus mode declares an
-- `accent_role` in its `presentation` block. `apply_colors` resolves it and
-- pushes the border/groupbar config live, so it is re-callable rather than
-- config-load-only: `hypr.hyprfocus.init` calls it again after a successful
-- mode transition (LEO-341), so the borders match the mode entered without a
-- `hyprctl reload`. The palette itself (macchiato/latte) is selected by the
-- sun timer or the user; the accent_role names a role *within* that palette.
-- Falling back to mauve when the mode has no accent or the role is unknown
-- keeps the desk legible even during the first load before any mode is set.
local Store = require("hypr.lib.store")

local PALETTES = { latte = true, frappe = true, macchiato = true, mocha = true }

-- Roles measured to clear the accent-on-base contrast target. On the light
-- latte palette lavender, peach and yellow (and any other pale role) fail
-- against its near-white base, so only mauve and blue may stand in for
-- "accent" there; the dark palettes pass every role, so nothing is restricted
-- for them. The same set is pinned in bin/,theme.sh's `accent_role` and
-- quickshell's Theme.qml, so the borders, the adapters and the bar cannot
-- disagree about what a mode's declared role actually resolves to.
local LATTE_PASSES = { mauve = true, blue = true }

local M = {}

-- Resolve the mode-scoped accent against an already-loaded palette table.
-- A missing or malformed declaration entry silently falls back to the
-- palette's own mauve, so a fresh desk or a declaration that has not yet
-- been edited is never broken. The palette name drives the contrast guard:
-- on latte a declared role that fails the accent-on-base target is treated
-- as missing, so mauve stands in rather than a border nobody can read.
---@param palette_name string? the active palette's name; nil means no guard
---@param theme table the loaded palette module
---@param mode string
---@return string
local function resolve_accent(palette_name, theme, mode)
  local decl = Store.define("hyprfocus")
  local role = decl:get("modes", mode, "presentation", "accent_role")
  if palette_name == "latte" and role and not LATTE_PASSES[role] then
    role = nil
  end
  if role and type(theme[role]) == "string" then
    return theme[role]
  end
  return theme.mauve
end

--- Push the border/groupbar `hl.config` block for a palette and mode.
---
--- Both arguments default to the live stores, so a bare call always reflects
--- current state; passing them explicitly is for callers that already
--- resolved one (and for tests, which pin a mode without touching the real
--- theme store).
---@param palette_name string? defaults to the theme store's `palette`
---@param mode string? defaults to the focus store's `mode`, or "work"
---@return table theme the resolved palette
---@return string accent the resolved accent colour
function M.apply_colors(palette_name, mode)
  palette_name = palette_name or Store.define("theme"):get("palette")
  if not PALETTES[palette_name] then
    palette_name = "macchiato"
  end
  local theme = require("hypr.themes." .. palette_name)

  mode = mode or Store.define("focus"):get("mode") or "work"
  local accent = resolve_accent(palette_name, theme, mode)

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
          inactive = theme.surface1,
          locked_active = theme.red,
          locked_inactive = theme.surface1,
        },
        -- The title has to read against both of those grounds, so it is not
        -- one colour: crust on the accent, a quieter subtext on the surface
        -- so the active tab stays the one that draws the eye.
        text_color = theme.crust,
        text_color_inactive = theme.subtext0,
        text_color_locked_active = theme.crust,
        text_color_locked_inactive = theme.subtext0,
      },
    },
  })

  return theme, accent
end

-- Config load is application-time (see the header): apply once immediately so
-- the desk is never left with hl's compiled-in defaults before the first
-- mode change.
M.apply_colors()

return M
