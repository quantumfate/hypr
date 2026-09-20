---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- The deck layout provider: wiring under test, not arithmetic (that is
--- tests/scene_deck_spec.lua). Mirrors tests/scene_provider_spec.lua's shape:
--- which scene a target set belongs to, that the visible member is placed,
--- and that a non-visible one is dispatched to hold.
local t = require("tests.harness")

local function fresh(scenes, windows, specs)
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
  _G.config = { host = { workspaces = { workspace_specs = specs or {} } } }
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

local TWO_COLUMNS = {
  default_name = "code",
  layout = "deck",
  gaps_in = 120,
  gaps_out = 50,
  columns = {
    { order = 1, share = 0.5, classes = { "Kitty-Main" } },
    { order = 2, share = 0.5, classes = { "Kitty-Panel" } },
  },
}

t.describe("gap precedence", function()
  t.it("a scene-declared gap wins over the host workspace-spec and the global", function()
    local specs = { { default_name = "code", gaps_in = 80, gaps_out = 40 } }
    local windows = {
      { address = "0x1", class = "Kitty-Main", workspace = { name = "code" } },
      { address = "0x2", class = "Kitty-Panel", workspace = { name = "code" } },
    }
    local _, provider = fresh({ TWO_COLUMNS }, windows, specs)
    local a = target("0x1", "Kitty-Main", "code")
    local b = target("0x2", "Kitty-Panel", "code")
    provider.recalculate({ area = AREA, targets = { a, b } })
    -- gaps_out 50 (scene, not spec's 40): row inset 50. gaps_in 120 (scene,
    -- not spec's 80): usable = 1000 - 100 - 120 = 780, first of two 0.5 shares
    -- = 390. The scene's declaration, not the host spec's, shapes both.
    t.eq(50, placed(a).x)
    t.eq(50, placed(a).y)
    t.eq(390, placed(a).w)
    t.eq(900, placed(a).h)
    t.eq(50, placed(b).y)
    t.eq(900, placed(b).h)
  end)

  t.it("falls back to the host workspace-spec gaps when the scene declares none", function()
    local specs = { { default_name = "code", gaps_in = 80, gaps_out = 40 } }
    local windows = { { address = "0x1", class = "Kitty-Main", workspace = { name = "code" } } }
    local _, provider = fresh({ CODE }, windows, specs)
    local a = target("0x1", "Kitty-Main", "code")
    provider.recalculate({ area = AREA, targets = { a } })
    t.eq(40, placed(a).x)
    t.eq(40, placed(a).y)
    t.eq(920, placed(a).w)
    t.eq(920, placed(a).h)
  end)

  t.it("honours an explicit scene zero rather than treating it as undeclared", function()
    local scene = {
      default_name = "code",
      layout = "deck",
      gaps_in = 0,
      gaps_out = 0,
      columns = { { order = 1, share = 1, classes = { "Kitty-Main" } } },
    }
    local specs = { { default_name = "code", gaps_in = 80, gaps_out = 40 } }
    local windows = { { address = "0x1", class = "Kitty-Main", workspace = { name = "code" } } }
    local _, provider = fresh({ scene }, windows, specs)
    local a = target("0x1", "Kitty-Main", "code")
    provider.recalculate({ area = AREA, targets = { a } })
    t.eq(0, placed(a).x)
    t.eq(0, placed(a).y)
    t.eq(1000, placed(a).w)
    t.eq(1000, placed(a).h)
  end)

  t.it("honours a sided gaps_out instead of collapsing it to one number (LEO-421)", function()
    local scene = {
      default_name = "code",
      layout = "deck",
      gaps_in = 0,
      gaps_out = { top = 10, right = 20, bottom = 30, left = 40 },
      columns = { { order = 1, share = 1, classes = { "Kitty-Main" } } },
    }
    local windows = { { address = "0x1", class = "Kitty-Main", workspace = { name = "code" } } }
    local _, provider = fresh({ scene }, windows)
    local a = target("0x1", "Kitty-Main", "code")
    provider.recalculate({ area = AREA, targets = { a } })
    t.eq(40, placed(a).x)
    t.eq(10, placed(a).y)
    t.eq(940, placed(a).w, "1000 - left(40) - right(20)")
    t.eq(960, placed(a).h, "1000 - top(10) - bottom(30)")
  end)
end)

t.describe("parking the non-visible members off-screen", function()
  t.it("places a non-visible member beyond the viewport, on the same workspace", function()
    -- LEO-402: a hidden member stays tiled where the compositor animates it.
    -- It travels off the monitor along the scroll axis rather than stacking
    -- behind the visible member, and it never leaves the workspace -- moving
    -- it to a special workspace is what made the scroll read as a cut.
    local windows = {
      { address = "0x1", class = "Kitty-Main", workspace = { name = "code" } },
      { address = "0x2", class = "Kitty-Main", workspace = { name = "code" } },
    }
    local stub, provider = fresh({ CODE }, windows)
    local a = target("0x1", "Kitty-Main", "code")
    local b = target("0x2", "Kitty-Main", "code")
    provider.recalculate({ area = AREA, targets = { a, b } })
    t.ok(placed(a), "the first arrival is shown by default")
    local hidden = placed(b)
    t.ok(hidden, "the hidden member is placed, not moved away")
    t.ok(hidden.y >= AREA.y + AREA.h or hidden.y + hidden.h <= AREA.y, "it sits outside the viewport")
    t.ok(hidden.y ~= placed(a).y, "it is not stacked behind the visible member")
    for _, action in ipairs(stub.dispatched) do
      t.ok(
        not (action.name == "dsp.window.move" and action.args[1].window == "address:0x2"),
        "a hidden member is never dispatched off the workspace"
      )
    end
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
