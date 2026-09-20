---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- Docks: where a scene's quickshell isles sit (docs/scenes.md "Docks").
--- Pure arithmetic over placed boxes, no compositor -- mirrors
--- tests/scene_layout_spec.lua.
local t = require("tests.harness")
local dock = require("hypr.lib.dock")

local MONITOR = { x = 0, y = 0, w = 1000, h = 800 }
local GAPS = { top = 60, right = 60, bottom = 60, left = 60 }

---One window filling the monitor minus the gaps: every gutter faces a screen
---edge, so nothing collapses for the wrong reason.
local SOLO = { x = 60, y = 60, w = 880, h = 680 }

---Two windows side by side: the left one's right gutter faces the other
---window, which is the inter-window case.
local LEFT = { x = 60, y = 60, w = 400, h = 680 }
local RIGHT = { x = 480, y = 60, w = 460, h = 680 }

---@param targets table<string, table>
---@param boxes table[]
---@param gaps_in number?
local function ctx(targets, boxes, gaps_in)
  return { monitor = MONITOR, targets = targets, boxes = boxes, gaps_out = GAPS, gaps_in = gaps_in or 0 }
end

t.describe("dock.resolve: where an isle lands", function()
  t.it("docks above the target for a top anchor, aligned to its left edge", function()
    local out =
      dock.resolve({ ["bar.left"] = { at = "top-left", of = "block:1" } }, ctx({ ["block:1"] = SOLO }, { SOLO }))
    local isle = out["bar.left"]
    t.eq("docked", isle.state)
    t.eq("up", isle.grow, "it grows away from the window, never into it")
    t.eq(SOLO.x, isle.anchor.x, "flush with the window's left edge")
    t.eq(SOLO.y, isle.anchor.y, "sitting on the window's top edge")
    t.eq(0, isle.region.y, "the gutter reaches the screen edge")
  end)

  t.it("centres the anchor along the edge for a -center anchor", function()
    local out =
      dock.resolve({ ["bar.center"] = { at = "top-center", of = "block:1" } }, ctx({ ["block:1"] = SOLO }, { SOLO }))
    t.eq(SOLO.x + SOLO.w / 2, out["bar.center"].anchor.x)
  end)

  t.it("stands the isle off the window by gaps_in, thinning the gutter by the same", function()
    local out =
      dock.resolve({ ["bar.left"] = { at = "top-left", of = "block:1" } }, ctx({ ["block:1"] = SOLO }, { SOLO }, 12))
    t.eq(SOLO.y - 12, out["bar.left"].anchor.y, "the standoff is the scene's own inner gap")
    t.eq(48, out["bar.left"].region.h, "the gutter is the outer gap minus that standoff")
  end)

  t.it("takes its orientation from the edge it docks to", function()
    local docks = {
      ["bar.a"] = { at = "top-left", of = "block:1" },
      ["bar.b"] = { at = "middle-left", of = "block:1" },
    }
    local out = dock.resolve(docks, ctx({ ["block:1"] = SOLO }, { SOLO }))
    t.eq("horizontal", out["bar.a"].orientation)
    t.eq("vertical", out["bar.b"].orientation, "a side gutter stacks its content")
  end)

  t.it("names a target by slot and by class, not only by block", function()
    local targets = { ["slot:dofus/browser"] = SOLO, ["class:Kitty-Main"] = SOLO }
    local docks = {
      ["bar.a"] = { at = "bottom-left", of = "slot:dofus/browser" },
      ["bar.b"] = { at = "top-right", of = "class:Kitty-Main" },
    }
    local out = dock.resolve(docks, ctx(targets, { SOLO }))
    t.eq("docked", out["bar.a"].state)
    t.eq("docked", out["bar.b"].state)
  end)
end)

t.describe("dock.resolve: collapse and the fallback ladder", function()
  t.it("never docks between two windows: the inter-window gutter is refused", function()
    -- The left window's right side faces the other window. `middle-right`
    -- has no second axis to switch to, so the isle steps down.
    local out = dock.resolve(
      { ["bar.a"] = { at = "middle-right", of = "block:1", fallback = { at = "middle-left", of = "screen" } } },
      ctx({ ["block:1"] = LEFT }, { LEFT, RIGHT })
    )
    t.eq("fallback", out["bar.a"].state)
  end)

  t.it("switches axis when the named gutter is inter-window and the other is free", function()
    -- `top-right` leads with the vertical word, and the top gutter faces the
    -- screen, so the isle docks there rather than collapsing.
    local out =
      dock.resolve({ ["bar.a"] = { at = "top-right", of = "block:1" } }, ctx({ ["block:1"] = LEFT }, { LEFT, RIGHT }))
    t.eq("docked", out["bar.a"].state)
    t.eq("up", out["bar.a"].grow)
  end)

  t.it("a lone window keeps its side dock, wherever its edge is", function()
    local out =
      dock.resolve({ ["bar.a"] = { at = "middle-right", of = "block:1" } }, ctx({ ["block:1"] = LEFT }, { LEFT }))
    t.eq("docked", out["bar.a"].state)
    t.eq(LEFT.x + LEFT.w, out["bar.a"].anchor.x, "it follows the window's own edge")
  end)

  t.it("an absent target steps down to the declared fallback", function()
    local out = dock.resolve(
      { ["bar.a"] = { at = "top-left", of = "block:9", fallback = { at = "top-left", of = "screen" } } },
      ctx({}, {})
    )
    t.eq("fallback", out["bar.a"].state)
    t.eq(MONITOR.x, out["bar.a"].anchor.x)
  end)

  t.it("an absent target with no declared fallback takes the same anchor on screen", function()
    -- The ladder's implicit tail: declared fallback, then this, then resting.
    -- It still reports `fallback`, so the consumer animates the snap when the
    -- window it was waiting for finally opens.
    local out = dock.resolve({ ["bar.a"] = { at = "middle-right", of = "block:9" } }, ctx({}, {}))
    t.eq("fallback", out["bar.a"].state)
    t.eq(MONITOR.w, out["bar.a"].anchor.x, "docked to the screen's own right edge")
  end)

  t.it("a withheld isle publishes `hidden`, which is not the same as resting", function()
    local out = dock.resolve({ ["bar.clock"] = false }, ctx({}, {}))
    t.eq("hidden", out["bar.clock"].state)
  end)
end)

t.describe("dock.resolve: two isles, one gutter", function()
  t.it("the first claimant keeps the region and the second steps down", function()
    local docks = {
      ["bar.a"] = { at = "top-left", of = "block:1" },
      ["bar.b"] = { at = "top-left", of = "block:1", fallback = { at = "bottom-left", of = "block:1" } },
    }
    local out = dock.resolve(docks, ctx({ ["block:1"] = SOLO }, { SOLO }))
    t.eq("docked", out["bar.a"].state, "sorted first by id, so it claims first")
    t.eq("fallback", out["bar.b"].state)
    t.eq("down", out["bar.b"].grow, "the loser took its own fallback, not the winner's spot")
  end)
end)

t.describe("dock.resolve: bounds", function()
  t.it("every published box is monitor-local, so a layer surface can use it as-is", function()
    local out = dock.resolve({ ["bar.a"] = { at = "top-left", of = "screen" } }, ctx({}, {}))
    t.eq(0, out["bar.a"].region.x)
    t.eq(0, out["bar.a"].anchor.x)
  end)
end)
