---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- The deck layout provider: wiring under test, not arithmetic (that is
--- tests/scene_deck_spec.lua). Mirrors tests/scene_provider_spec.lua's shape:
--- which scene a target set belongs to, that the visible member is placed,
--- and that a non-visible one is dispatched to hold.
local t = require("tests.harness")

---@param scenes table[]|nil raw scene declarations for the base store
---@param windows table|nil live windows `hl.get_windows` returns
---@param specs table|nil host workspace_specs for the gap ladder
---@param deck_doc table initial `deck-order` document (per-column records),
---for tests that must seed a scroll or order before the first pass
local function fresh(scenes, windows, specs, deck_doc)
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  local keyed = {}
  for _, raw in ipairs(scenes or {}) do
    keyed[raw.default_name] = raw
  end
  local deck_state = { doc = deck_doc or {} }
  package.loaded["hypr.lib.store"] = {
    define = function(name)
      if name == "deck-order" then
        return {
          get = function(_, key)
            return key == nil and deck_state.doc or deck_state.doc[key]
          end,
          put = function(_, next_doc)
            deck_state.doc = next_doc
          end,
          set = function() end,
        }
      end
      return {
        get = function()
          return { base = { scenes = keyed } }
        end,
        put = function() end,
        -- The real handle shallow-merges a patch; the dock publish uses it,
        -- and a fake missing it reads as "this store cannot be written".
        set = function() end,
      }
    end,
  }
  _G.config = { host = { workspaces = { workspace_specs = specs or {} } } }
  for _, mod in ipairs({
    "hypr.scene.spec",
    "hypr.scene.layout",
    "hypr.scene.deck",
    "hypr.scene.deck_order",
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

  t.it("honours an asymmetric host workspace-spec gaps_out side by side", function()
    -- The deck used to collapse a CssGap table to its `left` value and apply
    -- that scalar to every side, so a tighter top gap for the bar was ignored.
    local specs = {
      { default_name = "code", gaps_in = 0, gaps_out = { top = 10, right = 40, bottom = 40, left = 40 } },
    }
    local windows = { { address = "0x1", class = "Kitty-Main", workspace = { name = "code" } } }
    local _, provider = fresh({ CODE }, windows, specs)
    local a = target("0x1", "Kitty-Main", "code")
    provider.recalculate({ area = AREA, targets = { a } })
    t.eq(40, placed(a).x, "left outer gap reached the deck")
    t.eq(10, placed(a).y, "top outer gap reached the deck, not the left value")
    t.eq(920, placed(a).w, "width shrinks by left + right")
    t.eq(950, placed(a).h, "height shrinks by top + bottom")
  end)
end)

t.describe("the hold workspace stays out of sight", function()
  t.it("puts the hold special away when a move pulled it into view", function()
    -- Moving a window to a special makes the compositor SHOW that special, so
    -- a held member -- one the deck means to be invisible -- ends up drawn
    -- over whatever workspace is active, even one of another scene.
    local windows = {
      { address = "0x1", class = "Kitty-Main", workspace = { name = "code" } },
      { address = "0x2", class = "Kitty-Main", workspace = { name = "code" } },
    }
    local stub, provider = fresh({ CODE }, windows)
    stub.monitors = {
      {
        name = "DP-1",
        x = 0,
        y = 0,
        width = AREA.w,
        height = AREA.h,
        specialWorkspace = { name = "special:deck-hold" },
      },
    }
    provider.recalculate({
      area = AREA,
      targets = { target("0x1", "Kitty-Main", "code"), target("0x2", "Kitty-Main", "code") },
    })
    for _, timer in ipairs(stub.timers or {}) do
      timer.cb()
    end

    local hidden = false
    for _, action in ipairs(stub.dispatched) do
      if action.name == "dsp.workspace.toggle_special" then
        hidden = true
      end
    end
    t.ok(hidden, "the hold special is put away again")
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

  t.it("a reloaded provider walks the recorded order, not re-enumeration order", function()
    -- The user's arrangement of the column survives the reload that
    -- re-enumerates the same windows in the wrong (arrival) order: the
    -- recorded `order` leads, so the same two windows show what the record
    -- says is the first thing, not the first thing the compositor listed.
    local windows = {
      { address = "0x1", class = "Kitty-Main", workspace = { name = "code" } },
      { address = "0x2", class = "Kitty-Main", workspace = { name = "code" } },
    }
    local _, provider = fresh({ CODE }, windows, nil, { code = { [1] = { order = { "0x2", "0x1" }, scroll = 1 } } })
    local a = target("0x1", "Kitty-Main", "code")
    local b = target("0x2", "Kitty-Main", "code")
    provider.recalculate({ area = AREA, targets = { a, b } })
    t.ok(placed(b), "the recorded order shows 0x2, not the arrival-order 0x1")
    t.eq(nil, placed(a))
  end)

  t.it("a freshly arrived member is folded into the record and scrolled to", function()
    -- A window that just opened (never recorded) is new: the column scrolls
    -- to it so the desktop lands on what the user asked to open, and the
    -- merged order — recorded first, arrival appended — is what is stored
    -- for the next reload.
    local windows = {
      { address = "0x1", class = "Kitty-Main", workspace = { name = "code" } },
      { address = "0x2", class = "Kitty-Main", workspace = { name = "code" } },
    }
    local _, provider = fresh({ CODE }, windows, nil, { code = { [1] = { order = { "0x1" }, scroll = 1 } } })
    local a = target("0x1", "Kitty-Main", "code")
    local b = target("0x2", "Kitty-Main", "code")
    provider.recalculate({ area = AREA, targets = { a, b } })
    t.ok(placed(b), "the arrival took the column's shown place")
    t.eq(nil, placed(a), "the previously-shown member went to hold")
  end)

  t.it("asks a held member matching the scroll index to come home", function()
    -- The window is not in ctx.targets (it already left the workspace), so
    -- this pass must dispatch a move, not place it directly.
    local windows = {
      { address = "0x1", class = "Kitty-Main", workspace = { name = "special:deck-hold" } },
    }
    -- The recorded scroll of 1 is exactly the held member's place in the
    -- column, the state `mod+ctrl+j/k` persists between passes.
    local stub, provider = fresh({ CODE }, windows, nil, { code = { [1] = { order = { "0x1" }, scroll = 1 } } })
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

  -- The mode engine parks a withdrawn scene's windows in its own holding
  -- place. A deck that still counted them asked the compositor for them back
  -- -- so a coding window reappeared while a gaming mode was up, and the one
  -- the deck wanted hidden went to the deck's hold, a special the compositor
  -- then draws over whatever IS active.
  t.it("leaves a member the MODE has parked alone", function()
    local windows = {
      { address = "0x1", class = "Kitty-Main", workspace = { name = "special:hyprfocus-held" } },
      { address = "0x2", class = "Kitty-Main", workspace = { name = "special:hyprfocus-held" } },
    }
    local stub, provider = fresh({ CODE }, windows)
    provider.recalculate({ area = AREA, targets = { target("0xdead", "Kitty-Main", "code") } })
    for _, action in ipairs(stub.dispatched) do
      if action.name == "dsp.window.move" then
        t.eq(false, action.args[1].window == "address:0x1" or action.args[1].window == "address:0x2")
      end
    end
  end)

  -- The round trip that broke: leaving a deck scene parked its members on
  -- the mode's holding place, and the pass that ran while they were gone
  -- PRUNED them from the record. Homecoming then read as a first arrival —
  -- the column scrolled to the returning member and re-parked the one that
  -- had been visible, leaving the record pointing at a hidden member and
  -- focus on the wrong side of the desk.
  t.it("keeps a mode-held member's slot in the record", function()
    local windows = {
      { address = "0x2", class = "Kitty-Main", workspace = { name = "special:hyprfocus-held" } },
    }
    local _, provider = fresh({ CODE }, windows, nil, { code = { [1] = { order = { "0x1", "0x2" }, scroll = 1 } } })
    provider.recalculate({ area = AREA, targets = { target("0xdead", "Kitty-Main", "code") } })

    local record = require("hypr.scene.deck_order").get_all("code")[1]
    t.eq(2, #record.order, "the parked member keeps its slot")
    t.eq(1, record.scroll, "the recorded scroll is untouched while the member is held")
  end)

  t.it("a member home from the mode hold is a return, not an arrival", function()
    -- Restore brought both back tiled; the deck must show the recorded
    -- scroll's member (0x1) and re-park 0x2 — not scroll to 0x2.
    local windows = {
      { address = "0x1", class = "Kitty-Main", workspace = { name = "code" } },
      { address = "0x2", class = "Kitty-Main", workspace = { name = "code" } },
    }
    local stub, provider = fresh({ CODE }, windows, nil, { code = { [1] = { order = { "0x1", "0x2" }, scroll = 1 } } })
    provider.recalculate({
      area = AREA,
      targets = { target("0x1", "Kitty-Main", "code"), target("0x2", "Kitty-Main", "code") },
    })

    local record = require("hypr.scene.deck_order").get_all("code")[1]
    t.eq(1, record.scroll, "the recorded scroll survives the round trip")
    local parked = {}
    for _, action in ipairs(stub.dispatched) do
      if action.name == "dsp.window.move" and action.args[1].workspace == "special:deck-hold" then
        parked[action.args[1].window] = true
      end
    end
    t.eq(true, parked["address:0x2"] ~= nil, "the recorded-hidden member is parked again")
    t.eq(nil, parked["address:0x1"], "the recorded-visible member stays")
  end)
end)

return t
