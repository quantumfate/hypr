-- quantum-desktop: the ultrawide dual setup. Specs below are the same
-- skeleton as every host; the deltas are the engine blocks (split ratios the
-- panels ask for — 1.25 on the widescreen primary, 1.0 on normal-aspect
-- monitors) and this host's scene document.
-- Hosts shape (hypr/types.lua); workspace_specs entries are HL.WorkspaceRuleSpec.
---@type Hosts
return {
  primary_monitor = "DP-1",
  secondary_monitor = "DP-2",
  hyprlock_conf = os.getenv("HOME") .. "/.config/hypr/hyprlock.conf",
  -- #engine-block-layoutopts: Hyprland drops layoutopt on workspace rules
  -- (only layoutopt:orientation is implemented), so engine.layout_opts is
  -- consumed by hypr/events/layout_opts.lua, which rewrites the matching
  -- globals on workspace focus. Options may also be keyed by layout name to
  -- differ per layout on a workspace; see that file's header.
  workspaces = {
    workspace_specs = {
      {
        workspace = "1",
        default = true,
        default_name = "code",
        -- The scene layout: this workspace's arrangement is declared
        -- (hyprfocus scenes, see docs/scenes.md) rather than corrected after
        -- the fact. The terminals are one group, so there are two tiles
        -- however many project windows are open — the group left, the
        -- browser right, and the groupbar saying which terminal you are
        -- looking at.
        engine = {
          -- Two-tile ratio declaration; see docs/scenes.md.
          layout_opts = {
            dwindle = { default_split_ratio = 0.67 },
            scrolling = { column_width = 0.67 },
          },
        },
      },
      {
        workspace = "2",
        default_name = "creative",
        engine = { layout_opts = { dwindle = { default_split_ratio = 1.0 } } },
      },
      {
        workspace = "3",
        default_name = "proton",
        engine = { layout_opts = { dwindle = { default_split_ratio = 1.0 } } },
      },
      {
        workspace = "4",
        default_name = "gaming",
        -- No hardcoded gaps (LEO-190): the profile fills them per monitor
        -- like any other workspace, and solo_gaps frames the lone Dofus
        -- group when nothing else is open (LEO-191). The old gaps_out = 0
        -- meant edge-to-edge clients; the group rule already makes this a
        -- single tile, so the workspace is shaped by the system, not by a
        -- "zero means special" sentinel.
        --
        -- Opt out of solo framing (LEO-190/191): this scene's tile geometry
        -- is a fixed capture region. With framing on, the gaps flipped
        -- between the base profile and the +180 widen every time the tile
        -- count changed (group alone vs group + scene browser), which moves
        -- the OBS crop under you.
        engine = {
          -- Two-tile ratio declaration; see docs/scenes.md. A resize loop
          -- may correct drift internally; it is not this field.
          layout_opts = { dwindle = { default_split_ratio = 0.67 } },
          solo_gaps = "none",
        },
      },
      {
        workspace = "5",
        default_name = "media",
        monitor = "secondary",
        engine = { layout_opts = { dwindle = { default_split_ratio = 1.0 } } },
      },
      { workspace = "6", default_name = "logs", monitor = "secondary" },
      {
        workspace = "7",
        default_name = "misc",
        monitor = "secondary",
        engine = { layout_opts = { dwindle = { default_split_ratio = 1.25, special_scale_factor = 1 } } },
      },

      -- #special-workspaces: no monitor, no persistence — a special's
      -- lifetime is its open windows.
      { workspace = "special:comms" },
      { workspace = "special:music" },
      { workspace = "special:launcher" },
      {
        workspace = "special:ankama",
        -- Through the gate: focus mode refuses to START a game. An already
        -- running one is never touched (see ,focus-guard.sh).
        on_created_empty = "sh -c ',focus-guard.sh game && uwsm-app -- lutris lutris:rungameid/2'",
      },
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
    -- The scene document moved to the state store ($XDG_STATE_HOME
    -- scenes.json, seeded from hypr/scene/defaults.lua on first run) — a
    -- host file describes a machine, not how its windows sit.
  },
}
