-- The nested end-to-end host (tests/e2e/): selected with QF_HOST=e2e, never
-- by hostname. A nested Hyprland's own window is WAYLAND-1; `hyprctl output
-- create headless` adds HEADLESS-2 as the secondary. Workspace names are the
-- scenes in tests/e2e/fixtures/hyprfocus.json.
---@type Hosts
return {
  primary_monitor = "WAYLAND-1",
  secondary_monitor = "HEADLESS-2",
  hyprlock_conf = "/dev/null",
  workspaces = {
    workspace_specs = {
      { workspace = "1", default = true, default_name = "grouped" },
      { workspace = "2", default_name = "loose" },
      { workspace = "3", default_name = "arena" },
      { workspace = "11", default_name = "aside", monitor = "secondary" },
    },
    workspace_keys = { "plus", "bracketleft", "braceleft", "parenleft" },
  },
}
