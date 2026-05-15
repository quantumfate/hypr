-- Snapshot of the DMS-generated dms/layout.conf (taken 2026-05-16).
--
-- DMS still writes dms/layout.conf in hyprlang; hyprland.lua cannot `source`
-- hyprlang, so this Lua snapshot is loaded instead. Re-snapshot these values
-- whenever DMS changes your layout, or drop this file once DMS emits Lua.

hl.config({
  general = {
    gaps_in     = 4,
    gaps_out    = 4,
    border_size = 2,
  },
  decoration = {
    rounding = 6,
  },
})
