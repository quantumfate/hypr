-- The scenes store's serialized default: what Config seeds into
-- $XDG_STATE_HOME/scenes.json on first run, before any editor has written it.
--
-- This is data, not a host fork: the host files describe a MACHINE (workspace
-- ids, monitor names) and the store is meant to be edited by the user (LEO-239
-- from the shell, or a hand edit) — the default is only what a desk starts
-- with, exactly as a quickshell Store's `defaults` seeds its file. Keyed by
-- workspace `default_name`, never by id: ids are host data.
--
-- The shape here is the engine's raw language (`hypr/scene/spec.lua`
-- normalizes it). It is deliberately richer than the layout_opts-only tuple
-- the host files carried and not yet the full window-scene model
-- (quickshell's scenes schema, LEO-235's members/gaps/layout those documents
-- describe); the editor contract (LEO-239) owns that widening, in one store,
-- so this document and that model converge rather than coexist.
return {
  version = 1,
  scenes = {
    gaming = {
      blocks = {
        -- `collect`: a Dofus client dragged to another workspace mid-session
        -- comes back, because the group is the scene — a client left behind
        -- is one the roster and the OBS crop both stop seeing.
        { classes = { "Dofus.x64" }, group = true, order = 1, share = 0.67, collect = true },
        -- `deny`, not the default bar: this tile is a fixed region beside
        -- the group, and grouping it — even deliberately — would collapse
        -- the two-tile split the capture depends on.
        { classes = { "zen-gaming-media" }, order = 2, share = 0.33, guard = "deny" },
      },
      -- Classes that legitimately open here without belonging to a block.
      -- They are barred because `auto_group` grabs whatever opens while a
      -- group holds focus, and this workspace's main tile is a group.
      barred = { "steam_app_default", "steam_app_\\d+", "Ankama Launcher" },
      -- This scene's tile geometry is a fixed capture region, so a window
      -- that matches no block floats above it rather than taking a slot
      -- and shifting the split the crop is aimed at.
      strays = "float",
    },
    code = {
      blocks = {
        -- No `collect`: a project terminal you moved to another workspace is
        -- where you wanted it. Only the gaming group is cohesive enough to
        -- be worth dragging home.
        { classes = { "Kitty-Main", "Proj-[A-Za-z0-9_-]+" }, group = true, order = 1, share = 0.67 },
        { classes = { "zen-twilight", "firefox-developer-edition" }, order = 2, share = 0.33 },
      },
    },
  },
}
