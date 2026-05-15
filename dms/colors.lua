-- Snapshot of the DMS-generated dms/colors.conf (taken 2026-05-16).
--
-- DMS still writes dms/colors.conf in hyprlang; hyprland.lua cannot `source`
-- hyprlang, so this Lua snapshot is loaded instead. Re-snapshot these values
-- whenever you change your DMS theme, or drop this file once DMS emits Lua.

local primary = "rgb(c6a0f6)"
local outline = "rgb(6e738d)"
local err     = "rgb(ed8796)"

hl.config({
  general = {
    col = {
      active_border   = primary,
      inactive_border = outline,
    },
  },
  group = {
    col = {
      border_active          = primary,
      border_inactive        = outline,
      border_locked_active   = err,
      border_locked_inactive = outline,
    },
    groupbar = {
      col = {
        active          = primary,
        inactive        = outline,
        locked_active   = err,
        locked_inactive = outline,
      },
    },
  },
})
