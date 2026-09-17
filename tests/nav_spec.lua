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

return t
