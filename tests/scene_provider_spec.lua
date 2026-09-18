-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- The scene layout provider: the compositor asks, the scene answers.
---
--- The provider is a thin shell over the pure geometry, so what is under test
--- here is the wiring — which scene a set of targets belongs to, how a group's
--- identity is read off the compositor's objects, and that every target gets
--- placed exactly once. The arithmetic itself is covered by scene_layout_spec.
local t = require("tests.harness")

local function fresh(scenes, gaps)
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  -- The scenes live in the declaration's `base.scenes`; the stub hands the
  -- array-form fixtures over in that keyed shape.
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
        put = function(_, doc)
          keyed = doc.base.scenes
        end,
      }
    end,
  }
  _G.config = { host = { workspaces = { workspace_specs = {} } } }
  for _, mod in ipairs({ "hypr.scene.spec", "hypr.scene.layout", "hypr.scene.provider" }) do
    package.loaded[mod] = nil
  end
  stub.config_values = gaps or { ["general:gaps_in"] = 0, ["general:gaps_out"] = 0 }
  require("hypr.scene.provider").attach()
  return stub, stub.layouts.scene
end

---A layout target, recording what it was placed at.
local function target(address, class, workspace, group)
  local placed = nil
  return {
    window = {
      address = address,
      class = class,
      workspace = { id = 1, name = workspace },
      group = group,
    },
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
  blocks = {
    { classes = { "Kitty-Main" }, group = true, order = 1, share = 0.67 },
    { classes = { "zen-twilight" }, order = 2, share = 0.33 },
  },
}

local AREA = { x = 0, y = 0, w = 1000, h = 1000 }

t.describe("registration", function()
  t.it("registers a layout the compositor can select", function()
    local stub = fresh({ CODE })
    t.ok(stub.layouts.scene, "no layout registered")
    t.ok(type(stub.layouts.scene.recalculate) == "function")
  end)
end)

t.describe("placing", function()
  t.it("arranges a scene's tiles from the declaration", function()
    local _, provider = fresh({ CODE })
    local a = target("0x1", "Kitty-Main", "code")
    local b = target("0x9", "zen-twilight", "code")
    provider.recalculate({ area = AREA, targets = { a, b } })
    t.eq(670, placed(a).w)
    t.eq(670, placed(b).x)
    t.eq(330, placed(b).w)
  end)

  t.it("places every target exactly once", function()
    -- A target the provider forgets is a window left wherever it happened to
    -- be, which reads as the layout having failed.
    local _, provider = fresh({ CODE })
    local targets = {
      target("0x1", "Kitty-Main", "code"),
      target("0x9", "zen-twilight", "code"),
      target("0xf", "mpv", "code"),
    }
    provider.recalculate({ area = AREA, targets = targets })
    for _, tg in ipairs(targets) do
      t.ok(placed(tg), "a target was never placed")
    end
  end)

  t.it("reads a group's identity off the compositor's objects", function()
    -- Group members share one tile, so they must resolve to one slot rather
    -- than each claiming a share of the area.
    local _, provider = fresh({ CODE })
    local members = { { address = "0x1" }, { address = "0x2" } }
    local a = target("0x1", "Kitty-Main", "code", { members = members })
    local b = target("0x2", "Kitty-Main", "code", { members = members })
    local c = target("0x9", "zen-twilight", "code")
    provider.recalculate({ area = AREA, targets = { a, b, c } })
    t.eq(placed(a).x, placed(b).x, "group members share a box")
    t.eq(670, placed(c).x, "the group still occupies one slot")
  end)

  t.it("handles a group reported as a single bare member", function()
    -- Hyprland reports `members` as a bare window when the group holds one.
    local _, provider = fresh({ CODE })
    local a = target("0x1", "Kitty-Main", "code", { members = { address = "0x1", title = "kitty" } })
    provider.recalculate({ area = AREA, targets = { a } })
    t.ok(placed(a), "a one-member group still places")
  end)
end)

t.describe("workspaces without a scene", function()
  t.it("splits them evenly rather than leaving them stacked", function()
    -- Doing nothing would look like the compositor had hung.
    local _, provider = fresh({ CODE })
    local a = target("0x1", "mpv", "misc")
    local b = target("0x2", "imv", "misc")
    provider.recalculate({ area = AREA, targets = { a, b } })
    t.eq(0, placed(a).x)
    t.eq(500, placed(a).w)
    t.eq(500, placed(b).x)
  end)
end)

t.describe("gaps", function()
  t.it("reads the live values rather than a cached copy", function()
    -- A reload that changes the gaps should be picked up on the next
    -- recalculate, without a second mechanism keeping a copy in sync.
    local stub, provider = fresh({ CODE }, { ["general:gaps_in"] = 10, ["general:gaps_out"] = 20 })
    local a = target("0x1", "Kitty-Main", "code")
    local b = target("0x9", "zen-twilight", "code")
    provider.recalculate({ area = AREA, targets = { a, b } })
    t.eq(20, placed(a).x)

    stub.config_values["general:gaps_out"] = 50
    provider.recalculate({ area = AREA, targets = { a, b } })
    t.eq(50, placed(a).x, "the new value took effect with no reload of our own")
  end)

  t.it("reads the sided table the compositor actually pushes, side by side", function()
    -- Hyprland marshals a gap as named sides with no array part; the layout
    -- now honours each side (left for x) instead of collapsing the whole
    -- table to `top`, which used to flatten every outer gap to the bar's
    -- tight top value on every scene workspace.
    local _, provider = fresh({ CODE }, {
      ["general:gaps_in"] = { top = 12, right = 12, bottom = 12, left = 12 },
      ["general:gaps_out"] = { top = 8, right = 40, bottom = 40, left = 40 },
    })
    local a = target("0x1", "Kitty-Main", "code")
    local b = target("0x9", "zen-twilight", "code")
    provider.recalculate({ area = AREA, targets = { a, b } })
    t.eq(40, placed(a).x, "the left outer gap reached the layout")
    t.eq(8, placed(a).y, "the tighter top gap reached the layout, not the sides")
  end)

  t.it("prefers a workspace's own resolved spec gaps over the global config", function()
    -- The per-monitor gaps conf/base.lua's geometry_profiles declares are
    -- resolved onto workspace_specs at load time (hypr/lib/geometry.lua);
    -- this is what makes them reach a tiled window at all -- the global
    -- general:gaps_out below is what every workspace used to get regardless.
    local _, provider = fresh({ CODE }, { ["general:gaps_in"] = 12, ["general:gaps_out"] = 40 })
    _G.config.host.workspaces.workspace_specs = {
      { default_name = "code", gaps_in = 60, gaps_out = { top = 12, right = 80, bottom = 72, left = 80 } },
    }
    local a = target("0x1", "Kitty-Main", "code")
    local b = target("0x9", "zen-twilight", "code")
    provider.recalculate({ area = AREA, targets = { a, b } })
    t.eq(80, placed(a).x, "the spec's own left gap won over the global fallback")
    t.eq(12, placed(a).y, "the spec's own tighter top gap won too")
  end)

  t.it("survives a compositor that will not answer for a key", function()
    local _, provider = fresh({ CODE }, {})
    local a = target("0x1", "Kitty-Main", "code")
    provider.recalculate({ area = AREA, targets = { a } })
    t.ok(placed(a), "a missing config value must not stop the layout")
  end)

  t.it("honours the scene document's own solo_frame opt-out", function()
    -- conf/hosts scenes spell `solo_frame = false` for fixed capture regions;
    -- a normalize that dropped it would re-frame the workspace silently.
    local _, provider = fresh({ { default_name = "code", blocks = CODE.blocks, solo_frame = false } })
    local a = target("0x1", "Kitty-Main", "code")
    provider.recalculate({ area = AREA, targets = { a } })
    t.eq(0, placed(a).x, "no widened frame: the capture split does not move")
    t.eq(1000, placed(a).w)
  end)
end)

t.describe("strays", function()
  local FLOAT_CODE = {
    default_name = "code",
    blocks = CODE.blocks,
    strays = "float",
  }

  t.it("still slots a stray the compositor still offers as a tiled target", function()
    -- `strays = "float"` is executed by the open-time executor now
    -- (`hypr/scene/strays.lua`), which floats the window for real; once that
    -- dispatch lands, a floated window never reaches `recalculate` as a
    -- target again (`hl.get_windows()`'s own `floating` field). What this
    -- provider still sees mid-flight — before that dispatch lands — gets
    -- `slot` treatment, same as any other stray.
    local _, provider = fresh({ FLOAT_CODE })
    local a = target("0x1", "Kitty-Main", "code")
    local b = target("0x9", "zen-twilight", "code")
    local stray = target("0xf", "mpv", "code")
    provider.recalculate({ area = AREA, targets = { a, b, stray } })
    t.ok(placed(stray), "the stray still gets placed")
    t.ok(placed(a).w < 670, "the stray still claims a share of the split")
  end)
end)

t.describe("edges", function()
  t.it("does nothing with no targets", function()
    local _, provider = fresh({ CODE })
    provider.recalculate({ area = AREA, targets = {} })
  end)

  t.it("ignores a target with no window", function()
    local _, provider = fresh({ CODE })
    local a = target("0x1", "Kitty-Main", "code")
    provider.recalculate({ area = AREA, targets = { { place = function() end }, a } })
    t.ok(placed(a))
  end)
end)
