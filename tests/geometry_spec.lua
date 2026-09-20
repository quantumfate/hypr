-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")
local geometry = require("hypr.lib.geometry")

local aliases = { primary = "DP-1", secondary = "DP-2" }

t.describe("geometry.resolve", function()
  t.it("resolves primary/secondary sentinels to real output names", function()
    local specs = { { workspace = "1", monitor = "primary" }, { workspace = "5", monitor = "secondary" } }
    geometry.resolve(specs, aliases)
    t.eq("DP-1", specs[1].monitor)
    t.eq("DP-2", specs[2].monitor)
  end)

  t.it("fills unset gap fields from the profile's gaps_by_monitor", function()
    local specs = { { workspace = "1", monitor = "primary" } }
    geometry.resolve(specs, aliases, { primary = { gaps_in = 4, gaps_out = 8 } })
    t.eq(4, specs[1].gaps_in)
    t.eq(8, specs[1].gaps_out)
  end)

  t.it("the gaming workspace inherits profile gaps once it stops hardcoding 0 -- LEO-190", function()
    local gaming = {
      workspace = "gaming",
      monitor = "primary",
      border_size = 0,
      decorate = false,
    }
    geometry.resolve({ gaming }, aliases, { primary = { gaps_in = 4, gaps_out = 8 } })
    t.eq(4, gaming.gaps_in)
    t.eq(8, gaming.gaps_out)
    t.eq(0, gaming.border_size)
    t.eq(false, gaming.decorate)
  end)

  t.it("a spec that does hardcode gaps_out is still never overridden", function()
    local edge_to_edge = {
      workspace = "gaming",
      monitor = "primary",
      gaps_in = 0,
      gaps_out = 0,
    }
    geometry.resolve({ edge_to_edge }, aliases, { primary = { gaps_in = 4, gaps_out = 8 } })
    t.eq(0, edge_to_edge.gaps_in)
    t.eq(0, edge_to_edge.gaps_out)
  end)

  t.it("preserves a CssGap table's shape instead of flattening it to one number", function()
    -- gaps_out is an integer OR a table of named edges (top deliberately
    -- tighter than the rest, since the bar reserves its own height).
    local specs = { { workspace = "1", monitor = "secondary" } }
    local css_gap = { top = 8, right = 40, bottom = 40, left = 40 }
    geometry.resolve(specs, aliases, { secondary = { gaps_out = css_gap } })
    t.eq(css_gap, specs[1].gaps_out)
  end)

  t.it("a spec with no monitor role is untouched", function()
    local specs = { { workspace = "special:comms", layout = "scrolling" } }
    geometry.resolve(specs, aliases, { primary = { gaps_out = 8 } })
    t.eq(nil, specs[1].monitor)
    t.eq(nil, specs[1].gaps_out)
  end)
end)

t.describe("geometry.resolved_gaps", function()
  -- The published number is the distance from the monitor edge to the scene's
  -- outermost VISIBLE window. The layout's own gap (the engine's ladder) is
  -- only one term: the workspace rule's `gaps_out` lands outside the layout
  -- frame (the compositor takes it out of `ctx.area` first), and on a side the
  -- layout left inset its `gaps_in` and the border land back on top. A side the
  -- layout left flush keeps the work-area edge, so only the border lands.
  t.it("a scene layout resolves scene gaps_out first, spilled by layout.sides", function()
    local scenes = { code = { gaps_out = { top = 0, right = 60, bottom = 25, left = 25 } } }
    local specs = { { workspace = "1", default_name = "code", monitor = "DP-1", gaps_out = 30 } }
    local out = geometry.resolved_gaps(scenes, specs, 40)
    t.eq({ top = 30, right = 90, bottom = 55, left = 55 }, out["code"])
  end)

  t.it("adds the rule's gaps_in and the border to an inset side, never a flush one", function()
    local scenes = { code = { gaps_out = { left = 25 } } }
    local specs = { { default_name = "code", gaps_out = { left = 30, right = 0 }, gaps_in = 20 } }
    local out = geometry.resolved_gaps(scenes, specs, 40, { gaps_in = 24, border = 1 })
    t.eq({ top = 1, right = 1, bottom = 1, left = 76 }, out["code"])
  end)

  t.it("a scene layout's unnamed side is a real 0, never a fall-through", function()
    local scenes = { media = { gaps_out = { left = 91 } } }
    local specs = { { default_name = "media", gaps_out = { left = 5, right = 7 }, gaps_in = 3 } }
    local out = geometry.resolved_gaps(scenes, specs, 40, { gaps_in = 24, border = 1 })
    t.eq({ top = 1, right = 8, bottom = 1, left = 100 }, out["media"])
  end)

  t.it("a numeric scene gap applies to every side", function()
    local scenes = { code = { gaps_out = 55 } }
    local out = geometry.resolved_gaps(scenes, {}, 0)
    t.eq({ top = 55, right = 55, bottom = 55, left = 55 }, out["code"])
  end)

  t.it("a deck scene honours its sided gaps_out, per layout.sides, same as a scene layout", function()
    -- LEO-421: deck no longer collapses gaps_out to one symmetric number, so
    -- top (0) reads distinctly from left/right here.
    local scenes = { code = { layout = "deck", gaps_out = { top = 0, right = 60, bottom = 25, left = 25 } } }
    local out = geometry.resolved_gaps(scenes, {}, 0)
    t.eq({ top = 0, right = 60, bottom = 25, left = 25 }, out["code"])
  end)

  t.it("a deck's zero gap is flush on every side, so no gaps_in lands", function()
    local scenes = { code = { layout = "deck", gaps_out = 0 } }
    local specs = { { default_name = "code", gaps_out = { left = 30, right = 0 }, gaps_in = 20 } }
    local out = geometry.resolved_gaps(scenes, specs, 40, { gaps_in = 24, border = 1 })
    t.eq({ top = 1, right = 1, bottom = 1, left = 31 }, out["code"])
  end)

  t.it("a deck scene's unnamed side is a real 0 too, like a scene layout's", function()
    local scenes = { code = { layout = "deck", gaps_out = { top = 0, right = 60 } } }
    local specs = { { default_name = "code", gaps_out = 30 } }
    local out = geometry.resolved_gaps(scenes, specs, 40)
    t.eq({ top = 30, right = 90, bottom = 30, left = 30 }, out["code"])
  end)

  t.it("no scene gap falls to the host workspace-spec, keyed by default_name", function()
    local scenes = { code = {} }
    local specs = { { default_name = "code", gaps_out = 30 } }
    local out = geometry.resolved_gaps(scenes, specs, 40)
    t.eq({ top = 60, right = 60, bottom = 60, left = 60 }, out["code"])
  end)

  t.it("no scene or host gap falls to the global, folded per side", function()
    local scenes = { logs = {} }
    local out = geometry.resolved_gaps(scenes, {}, { top = 4, right = 56, bottom = 4, left = 8 })
    t.eq({ top = 8, right = 112, bottom = 8, left = 16 }, out["logs"])
  end)

  t.it("a bare-number global applies to every side", function()
    local scenes = { logs = {} }
    t.eq({ top = 80, right = 80, bottom = 80, left = 80 }, geometry.resolved_gaps(scenes, {}, 40)["logs"])
  end)
end)
