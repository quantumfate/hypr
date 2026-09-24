-- hypr/lib/nav.lua: the pure decisions behind LEO-344's tile/window/monitor
-- navigation binds. No `hl` here — plain scene/tile/monitor tables in,
-- indexes and key lists out.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")

local nav = require("hypr.lib.nav")

local TERMINALS = { classes = { "Kitty-Main" }, group = true, order = 1, share = 0.67 }
local BROWSER = { classes = { "zen-twilight" }, order = 2, share = 0.33 }

---@param blocks table[]
---@return Scene.Spec
local function scene(blocks)
  return { name = "code", blocks = blocks, barred = {}, strays = "slot", bindings = {}, moods = {}, machines = {} }
end

local function tile(address, class, group)
  return { address = address, class = class, group = group }
end

t.describe("nav.tile_order", function()
  t.it("orders declared blocks by their order field, then strays", function()
    local spec = scene({ TERMINALS, BROWSER })
    local tiles = nav.tile_order(spec, {
      tile("0x2", "zen-twilight"),
      tile("0x1", "Kitty-Main", "g1"),
      tile("0x3", "some-random-app"),
    })
    t.eq({ "block:1", "block:2", "stray:0x3" }, { tiles[1].key, tiles[2].key, tiles[3].key })
  end)

  t.it("collapses a group's members into one tile", function()
    local spec = scene({ TERMINALS })
    local tiles = nav.tile_order(spec, {
      tile("0x1", "Kitty-Main", "g1"),
      tile("0x2", "Kitty-Main", "g1"),
    })
    t.eq(1, #tiles)
    t.eq({ "0x1", "0x2" }, tiles[1].addresses)
    t.ok(tiles[1].group)
  end)

  t.it("keeps a stacked non-group block's windows as one tile, in arrival order", function()
    local stacked = { classes = { "logs" }, group = false, order = 1 }
    local spec = scene({ stacked })
    local tiles = nav.tile_order(spec, { tile("0x1", "logs"), tile("0x2", "logs") })
    t.eq(1, #tiles)
    t.eq({ "0x1", "0x2" }, tiles[1].addresses)
    t.ok(not tiles[1].group)
  end)
end)

t.describe("nav.tile_index / neighbor_tile / edge_tile", function()
  local spec = scene({ TERMINALS, BROWSER })
  local tiles = nav.tile_order(spec, { tile("0x1", "Kitty-Main", "g1"), tile("0x2", "zen-twilight") })

  t.it("finds the tile holding an address", function()
    t.eq(1, nav.tile_index(tiles, "0x1"))
    t.eq(2, nav.tile_index(tiles, "0x2"))
    t.eq(nil, nav.tile_index(tiles, "0x9"))
  end)

  t.it("returns the neighbour, or nil at the edge", function()
    t.eq(tiles[2], nav.neighbor_tile(tiles, 1, "right"))
    t.eq(nil, nav.neighbor_tile(tiles, 1, "left"))
    t.eq(nil, nav.neighbor_tile(tiles, 2, "right"))
  end)

  t.it("edge_tile picks the nearest-edge tile for the direction entered", function()
    t.eq(tiles[1], nav.edge_tile(tiles, "right"))
    t.eq(tiles[#tiles], nav.edge_tile(tiles, "left"))
  end)
end)

t.describe("nav.swap_order", function()
  local spec = scene({ TERMINALS, BROWSER })
  local tiles = nav.tile_order(spec, { tile("0x1", "Kitty-Main", "g1"), tile("0x2", "zen-twilight") })

  t.it("swaps two neighbouring tiles' key order", function()
    t.eq({ "block:2", "block:1" }, nav.swap_order(tiles, 1, "right"))
  end)

  t.it("is nil with no neighbour to swap with", function()
    t.eq(nil, nav.swap_order(tiles, 1, "left"))
    t.eq(nil, nav.swap_order(tiles, 2, "right"))
  end)
end)

t.describe("nav.window_neighbor", function()
  local addresses = { "0x1", "0x2", "0x3" }

  t.it("steps forward and back without wrapping", function()
    t.eq("0x2", nav.window_neighbor(addresses, "0x1", "next"))
    t.eq("0x3", nav.window_neighbor(addresses, "0x2", "next"))
    t.eq(nil, nav.window_neighbor(addresses, "0x3", "next"))
    t.eq(nil, nav.window_neighbor(addresses, "0x1", "prev"))
    t.eq("0x1", nav.window_neighbor(addresses, "0x2", "prev"))
  end)
end)

t.describe("nav.group_entry_order", function()
  t.it("puts the chosen address first, rest in arrival order", function()
    local members =
      { tile("0x1", "Kitty-Main", "g1"), tile("0x2", "Kitty-Main", "g1"), tile("0x3", "Kitty-Main", "g1") }
    t.eq({ "0x2", "0x1", "0x3" }, nav.group_entry_order(members, "0x2"))
  end)

  t.it("keeps arrival order when there is nothing to prefer", function()
    local members = { tile("0x1", "Kitty-Main", "g1"), tile("0x2", "Kitty-Main", "g1") }
    t.eq({ "0x1", "0x2" }, nav.group_entry_order(members, nil))
  end)

  t.it("keeps arrival order when the chosen address is not a member", function()
    local members = { tile("0x1", "Kitty-Main", "g1"), tile("0x2", "Kitty-Main", "g1") }
    t.eq({ "0x1", "0x2" }, nav.group_entry_order(members, "0x9"))
  end)
end)

t.describe("nav.tile_order picks a group's entry member via opts.enter", function()
  t.it("leads with opts.enter's pick (LEO-380 follow-up)", function()
    local spec = scene({ TERMINALS })
    local a, b, c = tile("0x1", "Kitty-Main", "g1"), tile("0x2", "Kitty-Main", "g1"), tile("0x3", "Kitty-Main", "g1")
    local tiles = nav.tile_order(spec, { a, b, c }, {
      enter = function()
        return "0x2"
      end,
    })
    t.eq({ "0x2", "0x1", "0x3" }, tiles[1].addresses)
  end)

  t.it("hands the group's own key to opts.enter", function()
    local spec = scene({ TERMINALS })
    local seen
    nav.tile_order(spec, { tile("0x1", "Kitty-Main", "g1"), tile("0x2", "Kitty-Main", "g1") }, {
      enter = function(_, group_key)
        seen = group_key
      end,
    })
    t.eq("g1", seen)
  end)

  t.it("keeps arrival order with no opts, or opts.enter returning nil", function()
    local spec = scene({ TERMINALS })
    local tiles = nav.tile_order(spec, { tile("0x1", "Kitty-Main", "g1"), tile("0x2", "Kitty-Main", "g1") })
    t.eq({ "0x1", "0x2" }, tiles[1].addresses)
  end)
end)

t.describe("nav.decide (LEO-380: mod+h/l as one pure decision)", function()
  local MONITORS = { { name = "DP-1", x = 0 }, { name = "DP-2", x = 1920 } }

  t.it("focuses the neighbouring tile when one exists", function()
    local spec = scene({ TERMINALS, BROWSER })
    local tiles = nav.tile_order(spec, { tile("0x1", "Kitty-Main", "g1"), tile("0x2", "zen-twilight") })
    local action = nav.decide({
      monitors = MONITORS,
      focused = "DP-1",
      tiles = tiles,
      active = "0x1",
      dir = "right",
    })
    t.eq({ kind = "window", address = "0x2" }, action)
  end)

  t.it("a group tile focuses opts.enter's pick, not the first address", function()
    local spec = scene({ TERMINALS, BROWSER })
    local a, b = tile("0x1", "Kitty-Main", "g1"), tile("0x2", "Kitty-Main", "g1")
    local tiles = nav.tile_order(spec, { a, b, tile("0x3", "zen-twilight") }, {
      enter = function()
        return "0x2"
      end,
    })
    local action = nav.decide({ monitors = MONITORS, focused = "DP-1", tiles = tiles, active = "0x3", dir = "left" })
    t.eq({ kind = "window", address = "0x2" }, action)
  end)

  t.it("an empty workspace (no active window) crosses to the adjacent monitor", function()
    local action = nav.decide({ monitors = MONITORS, focused = "DP-1", tiles = {}, active = nil, dir = "right" })
    t.eq({ kind = "monitor", name = "DP-2" }, action)
  end)

  t.it("landing on an empty workspace focuses the monitor, not a window", function()
    local spec = scene({ TERMINALS })
    local tiles = nav.tile_order(spec, { tile("0x1", "Kitty-Main", "g1") })
    local action = nav.decide({
      monitors = MONITORS,
      focused = "DP-1",
      tiles = tiles,
      active = "0x1",
      dir = "right",
      target = { tiles = {} },
    })
    t.eq({ kind = "monitor", name = "DP-2" }, action)
  end)

  t.it("landing where the other monitor has tiles focuses its edge tile", function()
    local spec = scene({ TERMINALS })
    local tiles = nav.tile_order(spec, { tile("0x1", "Kitty-Main", "g1") })
    local other = nav.tile_order(scene({ BROWSER }), { tile("0x9", "zen-twilight") })
    local action = nav.decide({
      monitors = MONITORS,
      focused = "DP-1",
      tiles = tiles,
      active = "0x1",
      dir = "right",
      target = { tiles = other },
    })
    t.eq({ kind = "window", address = "0x9" }, action)
  end)

  t.it("no adjacent monitor at the outer edge is a no-op", function()
    local spec = scene({ TERMINALS })
    local tiles = nav.tile_order(spec, { tile("0x1", "Kitty-Main", "g1") })
    local action = nav.decide({ monitors = MONITORS, focused = "DP-1", tiles = tiles, active = "0x1", dir = "left" })
    t.eq({ kind = "none" }, action)
  end)

  t.it("returning with the opposite key always works", function()
    local spec = scene({ TERMINALS, BROWSER })
    local tiles = nav.tile_order(spec, { tile("0x1", "Kitty-Main", "g1"), tile("0x2", "zen-twilight") })
    -- Landed on 0x2 (rightmost); pressing left steps back to the group tile.
    local back = nav.decide({ monitors = MONITORS, focused = "DP-1", tiles = tiles, active = "0x2", dir = "left" })
    t.eq({ kind = "window", address = "0x1" }, back)
  end)

  t.it("ignored monitors are never crossed onto", function()
    local monitors = { { name = "DP-1", x = 0 }, { name = "HDMI-A-1", x = 1920 } }
    local action = nav.decide({
      monitors = monitors,
      ignored = { "HDMI-A-1" },
      focused = "DP-1",
      tiles = {},
      active = nil,
      dir = "right",
    })
    t.eq({ kind = "none" }, action)
  end)
end)

t.describe("nav.monitor_order / adjacent_monitor", function()
  -- x descends for DP-2/HDMI-A-1 so the sort itself is exercised, not just
  -- passthrough of already-sorted input.
  local monitors = { { name = "HDMI-A-1", x = 5120 }, { name = "eDP-1", x = 0 } }

  t.it("orders monitors left to right by x", function()
    local ordered = nav.monitor_order(monitors)
    t.eq({ "eDP-1", "HDMI-A-1" }, { ordered[1].name, ordered[2].name })
  end)

  t.it("finds the adjacent monitor, or nil at the outer edge", function()
    local ordered = nav.monitor_order(monitors)
    t.eq("HDMI-A-1", nav.adjacent_monitor(ordered, "eDP-1", "right").name)
    t.eq(nil, nav.adjacent_monitor(ordered, "eDP-1", "left"))
    t.eq(nil, nav.adjacent_monitor(ordered, "HDMI-A-1", "right"))
  end)
end)

t.describe("nav.workspaces_on_monitor / nth_workspace", function()
  local placements = {
    { name = "code", output = "DP-1" },
    { name = "proton", output = "DP-1" },
    { name = "logs", output = "DP-2" },
  }

  t.it("filters to one monitor's scenes, in desk order", function()
    t.eq({ "code", "proton" }, nav.workspaces_on_monitor(placements, "DP-1"))
    t.eq({ "logs" }, nav.workspaces_on_monitor(placements, "DP-2"))
  end)

  t.it("nth_workspace is nil past the monitor's scene count — the no-op key", function()
    local names = nav.workspaces_on_monitor(placements, "DP-1")
    t.eq("code", nav.nth_workspace(names, 1))
    t.eq("proton", nav.nth_workspace(names, 2))
    t.eq(nil, nav.nth_workspace(names, 3))
  end)
end)

t.describe("nav.focus_unchanged", function()
  t.it("true when the active window's address did not move", function()
    t.eq(true, nav.focus_unchanged("0x1", "0x1"))
  end)

  t.it("true when there was, or is, no active window", function()
    t.eq(true, nav.focus_unchanged(nil, nil))
  end)

  t.it("false when the directional dispatch actually focused another window", function()
    t.eq(false, nav.focus_unchanged("0x1", "0x2"))
  end)
end)

t.describe("nav.symbol_for", function()
  t.it("spells workspace-row keys as their symbol, never a digit", function()
    t.eq("+", nav.symbol_for("plus"))
    t.eq("[", nav.symbol_for("bracketleft"))
    t.eq("*", nav.symbol_for("asterisk"))
  end)

  t.it("falls back to the raw key for one it does not know", function()
    t.eq("q", nav.symbol_for("q"))
  end)
end)

t.describe("nav.cycle_workspace (mod+TAB)", function()
  local names = { "code", "proton", "dofus" }

  t.it("steps in mode order and wraps both ways", function()
    t.eq("proton", nav.cycle_workspace(names, "code", "next"))
    t.eq("code", nav.cycle_workspace(names, "dofus", "next"))
    t.eq("dofus", nav.cycle_workspace(names, "code", "prev"))
  end)

  t.it("enters the list from a workspace outside it", function()
    t.eq("code", nav.cycle_workspace(names, "special:shelf-music", "next"))
    t.eq("dofus", nav.cycle_workspace(names, nil, "prev"))
  end)

  t.it("does nothing with nowhere to go", function()
    t.eq(nil, nav.cycle_workspace({}, "code", "next"))
    t.eq(nil, nav.cycle_workspace({ "code" }, "code", "next"))
  end)
end)

t.describe("ignored monitors", function()
  local IGNORED = { "HDMI-A-1" }
  local MONITORS = {
    { name = "DP-2", x = 0, activeWorkspace = { name = "logs" } },
    { name = "DP-1", x = 2560, activeWorkspace = { name = "code" } },
    { name = "HDMI-A-1", x = 7680, activeWorkspace = { name = "1" }, specialWorkspace = { name = "" } },
  }

  t.it("are never crossed onto", function()
    local ordered = nav.monitor_order(nav.usable_monitors(MONITORS, IGNORED))
    t.eq(nil, nav.adjacent_monitor(ordered, "DP-1", "right"))
    t.eq("DP-2", nav.adjacent_monitor(ordered, "DP-1", "left").name)
  end)

  t.it("redirect a targeted action to the primary", function()
    t.eq("DP-1", nav.target_monitor(IGNORED, "HDMI-A-1", "DP-1"))
    t.eq("DP-2", nav.target_monitor(IGNORED, "DP-2", "DP-1"))
    t.eq("DP-1", nav.target_monitor(IGNORED, nil, "DP-1"))
  end)

  t.it("move a window off, address-targeted, to the primary's active workspace", function()
    local w = { address = "0xa", workspace = { name = "1", monitor = { name = "HDMI-A-1" } } }
    t.eq({ { move = "0xa", workspace = "code" } }, nav.off_ignored(IGNORED, "DP-1", MONITORS, w))
    local fine = { address = "0xb", workspace = { name = "code", monitor = { name = "DP-1" } } }
    t.eq({}, nav.off_ignored(IGNORED, "DP-1", MONITORS, fine))
  end)

  t.it("re-show a special shown there on the primary", function()
    local monitors = {
      MONITORS[2],
      { name = "HDMI-A-1", specialWorkspace = { name = "special:shelf-ankama" } },
    }
    t.eq({ { show = "shelf-ankama" } }, nav.off_ignored(IGNORED, "DP-1", monitors, nil))
  end)

  t.it("do nothing on a host that ignores none", function()
    local w = { address = "0xa", workspace = { name = "1", monitor = { name = "HDMI-A-1" } } }
    t.eq({}, nav.off_ignored(nil, "DP-1", MONITORS, w))
  end)
end)

t.describe("undeclared workspaces (LEO-382)", function()
  local IGNORED = { "HDMI-A-1" }
  local SPECS = {
    { workspace = "1", default_name = "code", default = true, monitor = "DP-1" },
    { workspace = "3", default_name = "proton", monitor = "DP-1" },
    { workspace = "8", default_name = "obsidian-linear", monitor = "DP-2" },
    { workspace = "11", default_name = "media", monitor = "DP-2" },
  }

  t.it("moves a window on a workspace_specs does not name to the monitor's declared one", function()
    local w = { address = "0xa", workspace = { name = "2", monitor = { name = "DP-2" } } }
    t.eq({ { move = "0xa", workspace = "obsidian-linear" } }, nav.off_undeclared(SPECS, IGNORED, "DP-1", w))
  end)

  t.it("picks the monitor's default-marked spec over the first one declared", function()
    local w = { address = "0xa", workspace = { name = "2", monitor = { name = "DP-1" } } }
    t.eq({ { move = "0xa", workspace = "code" } }, nav.off_undeclared(SPECS, IGNORED, "DP-1", w))
  end)

  t.it("leaves a declared workspace alone", function()
    local w = { address = "0xa", workspace = { name = "proton", monitor = { name = "DP-1" } } }
    t.eq({}, nav.off_undeclared(SPECS, IGNORED, "DP-1", w))
  end)

  t.it("never moves a special", function()
    local w = { address = "0xa", workspace = { name = "special:hyprfocus-held", monitor = { name = "DP-2" } } }
    t.eq({}, nav.off_undeclared(SPECS, IGNORED, "DP-1", w))
  end)

  t.it("leaves an ignored monitor's undeclared workspace to off_ignored", function()
    local w = { address = "0xa", workspace = { name = "1", monitor = { name = "HDMI-A-1" } } }
    t.eq({}, nav.off_undeclared(SPECS, IGNORED, "DP-1", w))
  end)

  t.it("falls back to the primary's declared workspace when the monitor has none", function()
    local specs = {
      { workspace = "1", default_name = "code", default = true, monitor = "DP-1" },
    }
    local w = { address = "0xa", workspace = { name = "2", monitor = { name = "DP-2" } } }
    t.eq({ { move = "0xa", workspace = "code" } }, nav.off_undeclared(specs, IGNORED, "DP-1", w))
  end)

  t.it("does nothing with no window or workspace", function()
    t.eq({}, nav.off_undeclared(SPECS, IGNORED, "DP-1", nil))
    t.eq({}, nav.off_undeclared(SPECS, IGNORED, "DP-1", { address = "0xa" }))
  end)
end)

t.describe("nav.deck_tile_order", function()
  local SPEC = {
    columns = {
      { order = 1, classes = { "Kitty-Main" } },
      { order = 2, classes = { "zen" } },
    },
  }

  t.it("one Nav.Tile per non-empty column, shown member leading addresses", function()
    local tiles = nav.deck_tile_order(SPEC, {
      tile("a", "Kitty-Main"),
      tile("b", "Kitty-Main"),
      tile("c", "zen"),
    }, { [1] = { order = { "a", "b" }, scroll = 2 } })
    t.eq(2, #tiles)
    t.eq("deck:1", tiles[1].key)
    t.eq({ "b", "a" }, tiles[1].addresses)
    t.eq({ "a", "b" }, tiles[1].plain)
    t.eq(1, tiles[1].column)
    t.eq({ "c" }, tiles[2].addresses)
  end)

  t.it("drops an empty column entirely", function()
    local tiles = nav.deck_tile_order(SPEC, { tile("a", "Kitty-Main") }, {})
    t.eq(1, #tiles)
    t.eq("deck:1", tiles[1].key)
  end)

  t.it("clamps an out-of-range scroll index like deck.clamp_scroll", function()
    local tiles = nav.deck_tile_order(SPEC, {
      tile("a", "Kitty-Main"),
      tile("b", "Kitty-Main"),
    }, { [1] = { order = { "a", "b" }, scroll = 99 } })
    t.eq({ "b", "a" }, tiles[1].addresses)
  end)

  t.it("the recorded order leads the strip, re-enumeration order appended", function()
    -- A reload hands the windows back in arrival order, but the recorded
    -- order is the user's arrangement: the strip walks it first, and a
    -- genuinely new member (absent from the record) joins the tail.
    local tiles = nav.deck_tile_order(SPEC, {
      tile("a", "Kitty-Main"),
      tile("b", "Kitty-Main"),
      tile("d", "Kitty-Main"),
    }, { [1] = { order = { "b", "a" }, scroll = 1 } })
    t.eq({ "b", "a", "d" }, tiles[1].plain)
    t.eq({ "b", "a", "d" }, tiles[1].addresses)
    t.eq(1, tiles[1].column)
  end)

  t.it("composes with nav.decide across columns like scene tiles do", function()
    local tiles = nav.deck_tile_order(SPEC, {
      tile("a", "Kitty-Main"),
      tile("c", "zen"),
    }, {})
    local action = nav.decide({
      monitors = { { name = "DP-1", x = 0 } },
      focused = "DP-1",
      tiles = tiles,
      active = "a",
      dir = "right",
    })
    t.eq("window", action.kind)
    t.eq("c", action.address)
  end)
end)

t.describe("nav.restore_after_relocate", function()
  t.it("returns the monitor the user was on when it is usable", function()
    t.eq("DP-2", nav.restore_after_relocate({ "HDMI-A-1" }, "DP-2", "DP-1"))
  end)

  t.it("restores nothing when the user was already on the primary", function()
    t.eq(nil, nav.restore_after_relocate({ "HDMI-A-1" }, "DP-1", "DP-1"))
  end)

  t.it("restores nothing when the focused monitor was the ignored one", function()
    t.eq(nil, nav.restore_after_relocate({ "HDMI-A-1" }, "HDMI-A-1", "DP-1"))
  end)

  t.it("restores nothing when no monitor was focused", function()
    t.eq(nil, nav.restore_after_relocate({ "HDMI-A-1" }, nil, "DP-1"))
  end)
end)

t.describe("nav.special_workspace", function()
  t.it("reads the special from the live monitor shape", function()
    t.eq(
      "special:shelf-signal",
      nav.special_workspace({ active_special_workspace = { name = "special:shelf-signal" } })
    )
  end)

  t.it("also reads the older specialWorkspace shape", function()
    t.eq("special:shelf-signal", nav.special_workspace({ specialWorkspace = { name = "special:shelf-signal" } }))
  end)

  t.it("is nil when no special is shown", function()
    t.eq(nil, nav.special_workspace({ name = "DP-1" }))
    t.eq(nil, nav.special_workspace(nil))
  end)
end)

t.describe("nav.hide_special_if_shown", function()
  local function fire_timers(stub)
    for _, timer in ipairs(stub.timers) do
      timer.cb()
    end
  end

  t.it("toggles the special away when it is shown", function()
    local stub = require("tests.hl_stub").new()
    stub.monitors = { { name = "DP-1", specialWorkspace = { name = "special:hyprfocus-held" } } }
    _G.hl = stub
    nav.hide_special_if_shown("special:hyprfocus-held")
    fire_timers(stub)
    t.eq(1, #stub.dispatched)
    t.eq("dsp.workspace.toggle_special", stub.dispatched[1].name)
    t.eq({ "hyprfocus-held" }, stub.dispatched[1].args)
  end)

  t.it("does nothing when the special is not shown", function()
    local stub = require("tests.hl_stub").new()
    stub.monitors = { { name = "DP-1", specialWorkspace = { name = "" } } }
    _G.hl = stub
    nav.hide_special_if_shown("special:hyprfocus-held")
    fire_timers(stub)
    t.eq(0, #stub.dispatched)
  end)

  t.it("dispatches the toggle without the special: prefix", function()
    local stub = require("tests.hl_stub").new()
    stub.monitors = { { name = "DP-1", active_special_workspace = { name = "special:hyprfocus-held" } } }
    _G.hl = stub
    nav.hide_special_if_shown("special:hyprfocus-held")
    fire_timers(stub)
    t.eq("hyprfocus-held", stub.dispatched[1].args[1])
  end)
end)

return t
