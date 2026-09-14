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
    local specs = { { workspace = "special:comms", layout = "dwindle" } }
    geometry.resolve(specs, aliases, { primary = { gaps_out = 8 } })
    t.eq(nil, specs[1].monitor)
    t.eq(nil, specs[1].gaps_out)
  end)
end)
