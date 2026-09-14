-- quantum-laptop: one internal panel, an external slot. Workspaces live on
-- the primary; the spec defaults (persistent, the scene layout, primary
-- monitor) are filled by conf/host.lua — a file spells a field only to
-- deviate.
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
      { workspace = "4", default_name = "media" },
      {
        workspace = "5",
        default_name = "gaming",
        -- No hardcoded gaps (LEO-190): the profile fills them per monitor
        -- like any other workspace, and solo_gaps frames the lone Dofus
        -- group when nothing else is open (LEO-191). The old gaps_out = 0
        -- meant edge-to-edge clients; the group rule already makes this a
        -- single tile, so the workspace is shaped by the system, not by a
        -- "zero means special" sentinel.
        --
        -- Opt out of solo framing (LEO-190/191): this scene is a fixed
        -- capture region, not a lone window that wants breathing room.
        -- With framing on, the gaps flipped between the base profile and
        -- the +180 widen every time the tile count changed (group alone
        -- vs group + scene browser), which moves the OBS crop under you.
        engine = {
          -- Two-tile ratio declaration; see docs/scenes.md. A resize loop
          -- may correct drift internally; it is not this field.
          layout_opts = { dwindle = { default_split_ratio = 0.67 } },
          solo_gaps = "none",
        },
      },
      -- Same workspace arrangement as the desktop: every named workspace
      -- sits on primary (the fill default), no override spelled.
      { workspace = "6", default_name = "logs" },
      { workspace = "special:comms" },
      { workspace = "special:music" },
      { workspace = "special:launcher" },
      { workspace = "special:ankama", on_created_empty = "uwsm-app -- ,ankama-launcher.sh" },
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
