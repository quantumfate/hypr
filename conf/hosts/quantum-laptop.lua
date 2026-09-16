-- quantum-laptop: one internal panel, an external slot. Workspaces live on
-- the primary; the spec defaults (persistent, the scene layout, primary
-- monitor) are filled by conf/host.lua — a file spells a field only to
-- deviate.
--
-- Special workspaces are retired (LEO-265/330): every scene that used to live
-- in `special:*` is now an ordinary workspace admitted per mode. On the
-- laptop, secondary-pinned scenes use HDMI-A-1 when an external monitor is
-- connected; otherwise they fall back to primary.
-- Hosts shape (hypr/types.lua); workspace_specs entries are HL.WorkspaceRuleSpec.
---@type Hosts
return {
  primary_monitor = "eDP-1",
  secondary_monitor = "HDMI-A-1",
  hyprlock_conf = os.getenv("HOME") .. "/.config/hypr/hyprlock-laptop.conf",
  -- Gaps are geometry, resolved by output fingerprint (conf/base.lua's
  -- geometry_profiles), not by which host this is.
  kb_options = "caps:swapescape",
  workspaces = {
    workspace_specs = {
      {
        workspace = "1",
        default = true,
        default_name = "code",
        -- To fall back, set this to "dwindle" and reload; the layout is
        -- registered either way and nothing else depends on it.
        layout = "scene",
      },
      { workspace = "2", default_name = "creative" },
      { workspace = "3", default_name = "proton" },
      {
        workspace = "4",
        default_name = "dofus",
        engine = {
          layout_opts = { dwindle = { default_split_ratio = 0.67 } },
          solo_gaps = "none",
        },
      },
      { workspace = "5", default_name = "pokemon" },
      { workspace = "6", default_name = "steam-games" },
      { workspace = "7", default_name = "communication", monitor = "secondary" },
      {
        workspace = "8",
        default_name = "obsidian-linear",
        monitor = "secondary",
        engine = { layout_opts = { dwindle = { default_split_ratio = 0.5 } } },
      },
      { workspace = "9", default_name = "lutris", monitor = "secondary" },
      { workspace = "10", default_name = "steam", monitor = "secondary" },
      {
        workspace = "11",
        default_name = "media",
        monitor = "secondary",
        engine = { layout_opts = { dwindle = { default_split_ratio = 1.0 } } },
      },
      { workspace = "12", default_name = "logs", monitor = "secondary" },
      { workspace = "13", default_name = "misc", monitor = "secondary" },
      { workspace = "14", default_name = "ankama-launcher", monitor = "secondary" },
    },
    workspace_keys = {
      "plus",
      "bracketleft",
      "braceleft",
      "parenleft",
      "ampersand",
      "equal",
      "parenright",
      "braceright",
      "bracketright",
      "asterisk",
    },
  },
}
