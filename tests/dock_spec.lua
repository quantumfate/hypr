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
    -- The isle hugs the window and grows away from it, so its position
    -- follows the block on BOTH axes: a scene with a deeper top gap carries
    -- the isle down with it (docs/scenes.md "Docks").
    t.eq("up", isle.grow, "it grows away from the window, never into it")
    t.eq(SOLO.x, isle.anchor.x, "lined up with the window's left edge")
    t.eq(SOLO.y, isle.anchor.y, "sitting on the window's top edge")
    t.eq(0, isle.region.y, "the gutter reaches the screen edge")
    t.eq(SOLO.y, isle.region.h, "and runs all the way to the window")
  end)

  t.it("publishes which side of the isle the anchor is, not only the point", function()
    -- `grow` names the axis the isle extends along; along the EDGE the anchor
    -- may be the isle's start, middle or end. Without this the consumer read
    -- every anchor as a left edge, so a right-aligned isle ran off the screen.
    local docks = {
      ["bar.a"] = { at = "top-left", of = "block:1" },
      ["bar.b"] = { at = "top-center", of = "block:1" },
      ["bar.c"] = { at = "top-right", of = "block:1" },
    }
    local out = dock.resolve(docks, ctx({ ["block:1"] = SOLO }, { SOLO }))
    t.eq("start", out["bar.a"].align)
    t.eq("center", out["bar.b"].align)
    t.eq("end", out["bar.c"].align)
  end)

  t.it("centres the anchor along the edge for a -center anchor", function()
    local out =
      dock.resolve({ ["bar.center"] = { at = "top-center", of = "block:1" } }, ctx({ ["block:1"] = SOLO }, { SOLO }))
    t.eq(SOLO.x + SOLO.w / 2, out["bar.center"].anchor.x)
  end)

  t.it("stands the isle off the window by gaps_in", function()
    local inset =
      dock.resolve({ ["bar.a"] = { at = "top-left", of = "block:1" } }, ctx({ ["block:1"] = SOLO }, { SOLO }, 12))
    t.eq(SOLO.y - 12, inset["bar.a"].anchor.y, "the standoff is the scene's own inner gap")
    -- The whole gutter is still published: an isle standing in it has to
    -- clear both ends, and thinning the band by the standoff handed it every
    -- pixel of slack on one side.
    t.eq(SOLO.y, inset["bar.a"].region.h, "screen edge to window edge, whole")
  end)

  t.it("measures the gutter off the placed box, never off the declared gap", function()
    -- The gap ladder's answer and the geometry the compositor actually tiled
    -- were ~14px apart on a real desk, and the isles sat exactly that far off.
    -- The pass holds both boxes, so the gutter is a measurement, not a guess.
    local low = { x = 60, y = 200, w = 880, h = 540 }
    local out = dock.resolve({ ["bar.a"] = { at = "top-left", of = "block:1" } }, ctx({ ["block:1"] = low }, { low }))
    t.eq(200, out["bar.a"].region.h, "the window sits 200 below the screen edge, so the gutter is 200")
    t.eq(low.y, out["bar.a"].anchor.y, "and the isle hangs off the window's own edge")
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
    t.eq(LEFT.x + LEFT.w, out["bar.a"].region.x, "in the band that reaches the screen")
  end)

  t.it("an absent target steps down to the declared fallback while the scene has windows", function()
    local out = dock.resolve(
      { ["bar.a"] = { at = "top-left", of = "block:9", fallback = { at = "top-left", of = "screen" } } },
      ctx({}, { SOLO })
    )
    t.eq("fallback", out["bar.a"].state)
    t.eq(GAPS.left, out["bar.a"].anchor.x)
    t.eq(GAPS.top, out["bar.a"].anchor.y)
    t.eq("up", out["bar.a"].grow)
  end)

  t.it("an absent target with no declared fallback rests", function()
    -- The ladder is the isle's own declaration, then resting. An isle whose
    -- target is gone never invents an anchor the scene did not declare —
    -- that is what used to put one isle on a window gutter and its neighbour
    -- flush into the screen gap on the same workspace.
    local out = dock.resolve({ ["bar.a"] = { at = "middle-right", of = "block:9" } }, ctx({}, { SOLO }))
    t.eq("resting", out["bar.a"].state)
    t.eq(nil, out["bar.a"].anchor)
  end)

  t.it("an empty scene rests block-anchored isles, docked only where screen was declared", function()
    -- No tiles placed at all: a block target names nothing, so the isle
    -- rests — unless the isle's own declaration names the screen frame
    -- (directly or as its declared fallback), which is an explicit anchor.
    local out = dock.resolve({
      ["bar.a"] = { at = "top-left", of = "block:1", fallback = { at = "top-left", of = "screen" } },
      ["bar.b"] = { at = "top-right", of = "block:2" },
    }, ctx({}, {}))
    t.eq("fallback", out["bar.a"].state)
    t.eq(GAPS.left, out["bar.a"].anchor.x)
    t.eq(GAPS.top, out["bar.a"].anchor.y)
    t.eq("resting", out["bar.b"].state)
    t.eq(nil, out["bar.b"].anchor)
  end)

  t.it("an isle declared directly against `screen` still docks on an empty scene", function()
    -- `of = "screen"` as the first choice is not a fallback: it asked for the
    -- screen frame on purpose, windows or none.
    local out = dock.resolve({ ["bar.a"] = { at = "top-left", of = "screen" } }, ctx({}, {}))
    t.eq("docked", out["bar.a"].state)
    t.eq(GAPS.left, out["bar.a"].anchor.x)
  end)

  t.it("a withheld isle publishes `hidden`, which is not the same as resting", function()
    local out = dock.resolve({ ["bar.clock"] = false }, ctx({}, {}))
    t.eq("hidden", out["bar.clock"].state)
  end)
end)

t.describe("dock.resolve: the side-leading corners", function()
  t.it("left-bottom stands in the left gutter, aligned to the window's bottom", function()
    local out =
      dock.resolve({ ["bar.a"] = { at = "left-bottom", of = "block:1" } }, ctx({ ["block:1"] = SOLO }, { SOLO }))
    local isle = out["bar.a"]
    t.eq("docked", isle.state)
    t.eq("left", isle.grow, "the left gutter is the dominant one, not the bottom")
    t.eq(SOLO.x, isle.anchor.x)
    t.eq(SOLO.y + SOLO.h, isle.anchor.y, "aligned to the window's bottom edge")
    t.eq("vertical", isle.orientation, "a side gutter stacks its content")
  end)

  t.it("right-top stands in the right gutter, aligned to the window's top", function()
    local out =
      dock.resolve({ ["bar.a"] = { at = "right-top", of = "block:1" } }, ctx({ ["block:1"] = SOLO }, { SOLO }))
    t.eq("right", out["bar.a"].grow, "away from the window, into the right gutter")
    t.eq(SOLO.y, out["bar.a"].anchor.y)
  end)

  t.it("falls to the other edge when its own gutter faces a window", function()
    -- LEFT's right side faces RIGHT, so `right-bottom` takes the bottom edge
    -- it also names rather than docking between the two windows.
    local out = dock.resolve(
      { ["bar.a"] = { at = "right-bottom", of = "block:1" } },
      ctx({ ["block:1"] = LEFT }, { LEFT, RIGHT })
    )
    t.eq("docked", out["bar.a"].state)
    t.eq("down", out["bar.a"].grow, "the bottom gutter, away from the window")
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

  t.it("two ends of the same gutter are two spots, and both dock", function()
    -- The shape every scene declares: the media isle at the left of a
    -- block's top gutter, the clock at its right. Keying the claim on the
    -- gutter alone made the clock lose this race in every scene, so it never
    -- once docked where it was declared.
    local docks = {
      ["bar.center"] = { at = "top-left", of = "block:1" },
      ["bar.clock"] = { at = "top-right", of = "block:1" },
    }
    local out = dock.resolve(docks, ctx({ ["block:1"] = SOLO }, { SOLO }))
    t.eq("docked", out["bar.center"].state)
    t.eq("docked", out["bar.clock"].state, "the other end of the gutter is free")
    t.eq(SOLO.x, out["bar.center"].anchor.x)
    t.eq(SOLO.x + SOLO.w, out["bar.clock"].anchor.x, "aligned to the window's right edge")
  end)
end)

t.describe("dock.resolve: bounds", function()
  t.it("a screen dock respects the outer gap instead of hugging the monitor edge", function()
    local out = dock.resolve({ ["bar.a"] = { at = "top-left", of = "screen" } }, ctx({}, {}))
    t.eq(GAPS.left, out["bar.a"].region.x)
    t.eq(GAPS.left, out["bar.a"].anchor.x)
    t.eq(GAPS.top, out["bar.a"].anchor.y)
    t.eq(GAPS.top, out["bar.a"].region.h)
    t.eq("up", out["bar.a"].grow, "grows away from the content area into the gap")
  end)

  t.it("a screen dock grows into the gap from the content edge", function()
    local out = dock.resolve({ ["bar.a"] = { at = "top-right", of = "screen" } }, ctx({}, {}))
    t.eq("up", out["bar.a"].grow)
    t.eq(GAPS.top, out["bar.a"].anchor.y)
    t.eq(MONITOR.w - GAPS.right, out["bar.a"].anchor.x)
    t.eq(GAPS.top, out["bar.a"].region.h)
  end)

  t.it("a screen dock's band is the gap, not the distance to a tile", function()
    -- The screen target is the monitor minus the outer gap, so tiles inside
    -- the content area do not shorten the band; the isle stays in the gap.
    local out = dock.resolve({ ["bar.a"] = { at = "top-left", of = "screen" } }, ctx({}, { SOLO }))
    t.eq(GAPS.top, out["bar.a"].region.h)
    t.eq(GAPS.top, out["bar.a"].anchor.y)
  end)

  t.it("the inward gutter of a bottom/right screen dock sits inside the gap", function()
    local out = dock.resolve({ ["bar.a"] = { at = "middle-right", of = "screen" } }, ctx({}, { SOLO }))
    t.eq("right", out["bar.a"].grow, "grows away from the content area into the right gap")
    t.eq(MONITOR.w - GAPS.right, out["bar.a"].region.x, "the band starts at the inner edge of the right gap")
    t.eq(GAPS.right, out["bar.a"].region.w)
  end)
end)
