-- The nested end-to-end host (tests/e2e/): selected with QF_HOST=e2e, never
-- by hostname. A nested Hyprland's own window is WAYLAND-1; `hyprctl output
-- create headless` adds HEADLESS-2 as the secondary. Workspace names are the
-- scenes in tests/e2e/fixtures/hyprfocus.json.
--
-- WAYLAND-1's mode is pinned small (1280x360, the 32:9 shape of the desktop ultrawide) so the nested window on the
-- live desktop, and any `hq shot` screenshot of it, stay cheap — this is a
-- host DATA file with nowhere to call hl.monitor(), so it's set at runtime
-- instead, right after boot: tests/e2e/lib.sh's e2e_boot (both `just e2e`
-- scenarios and `hq up`) issues `hyprctl keyword monitor` for it.
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
      -- docs/deck.md's live spike (LEO-349): a sandboxed fixture scene only,
      -- never a real one — see tests/e2e/fixtures/hyprfocus.json's
      -- "deck-test" and tests/e2e/scenarios/90_deck.sh.
      { workspace = "4", default_name = "deck-test", layout = "deck" },
      -- `,proj.sh`'s own target workspace: a fixture scene
      -- with the same `Proj-*` group block the real "code" scene declares,
      -- so 95_project_group.sh exercises the actual grouping engine a
      -- project relies on, not a stand-in class.
      { workspace = "5", default_name = "code" },
      -- LEO-349: the real "code" scene's shape, mirrored with e2e-safe
      -- classes — a deck project column (one block per project, per
      -- docs/columns.md §11's "declared by hand" fallback, so three
      -- concurrently open projects stay three separate groups) beside a
      -- stack-behaving browser column. See tests/e2e/scenarios/97_code_deck.sh.
      { workspace = "6", default_name = "code-deck", layout = "deck" },
    },
    workspace_keys = { "plus", "bracketleft", "braceleft", "parenleft" },
  },
}
