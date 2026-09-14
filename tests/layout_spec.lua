-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")
local layout = require("hypr.lib.layout")

t.describe("layout", function()
  t.it("dispatch() calls the handler registered for the active workspace's layout", function()
    local called_with
    layout.register("dwindle", {
      focus_left = function(ctx)
        called_with = ctx
      end,
    })

    function hl.get_active_workspace()
      return { tiled_layout = "dwindle" }
    end

    layout.dispatch("focus_left")
    t.ok(called_with, "expected the dwindle handler to run")
    t.eq("dwindle", called_with.layout)
  end)

  t.it("falls back to register_fallback when the active layout registered nothing", function()
    local fallback_ran = false
    layout.register_fallback({
      swap_left = function()
        fallback_ran = true
      end,
    })

    function hl.get_active_workspace()
      return { tiled_layout = "monocle" } -- no monocle handler registered above
    end

    layout.dispatch("swap_left")
    t.ok(fallback_ran, "expected the fallback handler to run")
  end)

  t.it("prefers the active special workspace over the normal one", function()
    local seen_layout
    layout.register("scrolling", {
      focus_up = function(ctx)
        seen_layout = ctx.layout
      end,
    })

    function hl.get_active_special_workspace()
      return { tiled_layout = "scrolling" }
    end
    function hl.get_active_workspace()
      return { tiled_layout = "dwindle" }
    end

    layout.dispatch("focus_up")
    t.eq("scrolling", seen_layout)
  end)

  t.it("get_submaps() returns every submap registered via register_submap, in order", function()
    local spec_a = { layout = "dwindle", key = "d", entries = {} }
    local spec_b = { layout = "master", key = "m", entries = {} }
    layout.register_submap(spec_a)
    layout.register_submap(spec_b)

    local submaps = layout.get_submaps()
    t.eq(spec_a, submaps[#submaps - 1])
    t.eq(spec_b, submaps[#submaps])
  end)

  t.it("rule_layout() spells builtins bare and prefixes custom Lua layouts", function()
    t.eq("dwindle", layout.rule_layout("dwindle"))
    t.eq("master", layout.rule_layout("master"))
    t.eq("lua:scene", layout.rule_layout("scene"))
  end)
end)
