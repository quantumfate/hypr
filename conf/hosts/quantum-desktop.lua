-- quantum-desktop: the ultrawide dual setup. Specs below are the same
-- skeleton as every host; the deltas are the engine blocks (split ratios the
-- panels ask for — 1.25 on the widescreen primary, 1.0 on normal-aspect
-- monitors) and this host's scene document.
--
-- Special workspaces are retired (LEO-265/330): every scene that used to live
-- in `special:*` is now an ordinary workspace admitted per mode. The monitor
-- field is only the load-time default: each mode places its scenes by monitor
-- role (hyprfocus `scenes[].monitor`), and that placement wins on entry.
-- Hosts shape (hypr/types.lua); workspace_specs entries are HL.WorkspaceRuleSpec.
---@type Hosts
return {
  primary_monitor = "DP-1",
  secondary_monitor = "DP-2",
  -- The case panel: connected, never a target. Nothing is placed, shown or
  -- focused there; a window that lands on it moves to the primary. It is
  -- rotated 800x1280 and carries no bar (quickshell's Bar.qml excludes it the
  -- same way); were it ever un-ignored it would want a tight gap profile of
  -- its own (roughly gaps_in 16, gaps_out 16 -- there is little panel to
  -- spend on air), added to conf/base.lua's `geometry_profiles` alongside
  -- primary/secondary rather than invented here.
  ignored_monitors = { "HDMI-A-1" },
  hyprlock_conf = os.getenv("HOME") .. "/.config/hypr/hyprlock.conf",
  -- #engine-block-layoutopts: Hyprland drops layoutopt on workspace rules
  -- (only layoutopt:orientation is implemented), so engine.layout_opts is
  -- consumed by hypr/events/layout_opts.lua, which rewrites the matching
  -- globals on workspace focus. Options may also be keyed by layout name to
  -- differ per layout on a workspace; see that file's header.
  workspaces = {
    workspace_specs = {
      -- Shared across work + study modes. The scene layout: this workspace's
      -- arrangement is declared (hyprfocus scenes, see docs/scenes.md) rather
      -- than corrected after the fact. The terminals are one group, so there
      -- are two tiles however many project windows are open — the group left,
      -- the browser right, and the groupbar saying which terminal you are
      -- looking at.
      -- Deck (docs/deck.md): the project column flips through open project
      -- groups, the browser column sits beside it. Column widths are the
      -- scene's own declared `share` (docs/scenes.md), not a layout_opts
      -- field — the stale `scrolling.column_width` this workspace carried
      -- under the old "scrolling" builtin layout is dropped along with the
      -- switch, since "deck" reads no layout_opts of its own.
      { workspace = "1", default = true, default_name = "code", layout = "deck" },
      -- Proton shared across gaming + work + study modes. The 50/50 split
      -- (mail left, pass companion right) is declared by the scene.
      { workspace = "3", default_name = "proton" },
      -- Dofus: the primary gaming workspace. The tile geometry is a fixed
      -- capture region, so this scene's declaration must opt out of solo
      -- framing itself (`solo_frame = false`); the per-host opt-out field
      -- that used to live here belonged to a now-retired framing module.
      -- `hide_groupbar_for` (LEO-380 live complaint): the physical order fix
      -- already puts the team roster in the right visual order, but the user
      -- also asked to drop the groupbar here specifically. Hyprland ties the
      -- groupbar to the window rule `decorate` effect (hypr/workspaces.lua),
      -- which also drops the border and shadow — there is no groupbar-only
      -- knob (source-verified against Hyprland 0.56).
      { workspace = "4", default_name = "dofus", engine = { hide_groupbar_for = { "Dofus.x64" } } },
      -- Pokemon: emulator + streaming media. On primary beside dofus.
      { workspace = "5", default_name = "pokemon" },
      -- Steam games: fullscreen proton/steam windows, no split.
      { workspace = "6", default_name = "steam-games" },
      -- Obsidian + Linear side-by-side. Shared by work + study modes.
      { workspace = "8", default_name = "obsidian-linear", monitor = "secondary" },
      -- Media: fullscreen media player.
      { workspace = "11", default_name = "media", monitor = "secondary" },
      -- Logs: tmux log workspace, secondary.
      { workspace = "12", default_name = "logs", monitor = "secondary" },
    },
    -- Communication, Lutris, Steam and the Ankama Launcher are shelves now
    -- (conf/base.lua `shelves`), not workspaces.
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
    -- Scenes live in the hyprfocus declaration's `base.scenes` — a host
    -- file describes a machine, not how its windows sit.
  },
}
