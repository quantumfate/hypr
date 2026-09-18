---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- The deck layout provider: wiring under test, not arithmetic (that is
--- tests/scene_deck_spec.lua). Mirrors tests/scene_provider_spec.lua's shape:
--- which scene a target set belongs to, that the visible member is placed,
--- and that a non-visible one is dispatched to hold.
local t = require("tests.harness")

local function fresh(scenes, windows)
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  local keyed = {}
  for _, raw in ipairs(scenes or {}) do
    keyed[raw.default_name] = raw
  end
  package.loaded["hypr.lib.store"] = {
    define = function()
      return {
        get = function()
          return { base = { scenes = keyed } }
        end,
        put = function() end,
      }
    end,
  }
  _G.config = { host = { workspaces = { workspace_specs = {} } } }
  for _, mod in ipairs({
    "hypr.scene.spec",
    "hypr.scene.layout",
    "hypr.scene.deck",
    "hypr.scene.deck_scroll",
    "hypr.scene.provider",
    "hypr.scene.deck_provider",
  }) do
    package.loaded[mod] = nil
  end
  stub.config_values = { ["general:gaps_in"] = 0, ["general:gaps_out"] = 0 }
  stub.get_windows = function()
    return windows or {}
  end
  local deck_provider = require("hypr.scene.deck_provider")
  deck_provider.attach()
  return stub, stub.layouts.deck
end

local function target(address, class, workspace)
  local placed = nil
  return {
    window = { address = address, class = class, workspace = { id = 1, name = workspace } },
    place = function(_, box)
      placed = box
    end,
    box = function()
      return placed
    end,
  }
end

local function placed(target_)
  return target_.box()
end

local CODE = {
  default_name = "code",
  layout = "deck",
  columns = {
    { order = 1, share = 1, classes = { "Kitty-Main" } },
  },
}

local AREA = { x = 0, y = 0, w = 1000, h = 1000 }

t.describe("registration", function()
  t.it("registers a layout the compositor can select", function()
    local stub = fresh({ CODE })
    t.ok(stub.layouts.deck, "no layout registered")
    t.ok(type(stub.layouts.deck.recalculate) == "function")
  end)
end)

t.describe("placing the visible member", function()
  t.it("places the shown window at full column height", function()
    local windows = { { address = "0x1", class = "Kitty-Main", workspace = { name = "code" } } }
    local _, provider = fresh({ CODE }, windows)
    local a = target("0x1", "Kitty-Main", "code")
    provider.recalculate({ area = AREA, targets = { a } })
    t.eq(1000, placed(a).h)
    t.eq(1000, placed(a).w)
  end)

  t.it("does nothing for a workspace with no deck scene", function()
    local _, provider = fresh({ CODE }, {})
    local a = target("0x1", "mpv", "misc")
    provider.recalculate({ area = AREA, targets = { a } })
    t.eq(nil, placed(a))
  end)
end)

t.describe("holding the non-visible members", function()
  t.it("dispatches a still-tiled non-visible member to the hold workspace", function()
    local windows = {
      { address = "0x1", class = "Kitty-Main", workspace = { name = "code" } },
      { address = "0x2", class = "Kitty-Main", workspace = { name = "code" } },
    }
    local stub, provider = fresh({ CODE }, windows)
    local a = target("0x1", "Kitty-Main", "code")
    local b = target("0x2", "Kitty-Main", "code")
    provider.recalculate({ area = AREA, targets = { a, b } })
    t.ok(placed(a), "the first arrival is shown by default")
    t.eq(nil, placed(b))
    local held = false
    for _, action in ipairs(stub.dispatched) do
      if action.name == "dsp.window.move" and action.args[1].window == "address:0x2" then
        t.eq("special:deck-hold", action.args[1].workspace)
        held = true
      end
    end
    t.ok(held, "the second member was dispatched to hold")
  end)

  t.it("asks a held member matching the scroll index to come home", function()
    -- The window is not in ctx.targets (it already left the workspace), so
    -- this pass must dispatch a move, not place it directly.
    local windows = {
      { address = "0x1", class = "Kitty-Main", workspace = { name = "special:deck-hold" } },
    }
    require("hypr.scene.deck_scroll").reset()
    require("hypr.scene.deck_scroll").set("code", 1, 1)
    local stub, provider = fresh({ CODE }, windows)
    require("hypr.scene.deck_scroll").set("code", 1, 1)
    -- No targets: the window is not tiled on the workspace yet, so
    -- recalculate would normally get nothing to iterate — a held member
    -- only re-enters via `hl.get_windows()`, gathered independent of targets.
    provider.recalculate({ area = AREA, targets = { target("0xdead", "Kitty-Main", "code") } })
    local moved = false
    for _, action in ipairs(stub.dispatched) do
      if action.name == "dsp.window.move" and action.args[1].window == "address:0x1" then
        t.eq("name:code", action.args[1].workspace)
        moved = true
      end
    end
    t.ok(moved, "the held member was asked home")
  end)
end)

return t
