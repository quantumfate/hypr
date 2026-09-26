---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- Areas: a scene's published `work` and `columns` (docs/scenes.md "Areas").
--- Pure arithmetic over placed boxes, no compositor -- mirrors
--- tests/dock_spec.lua.
local t = require("tests.harness")
local area = require("hypr.lib.area")

t.describe("area.corners: a box's four corners", function()
  t.it("reports all four, monitor-local", function()
    local c = area.corners({ x = 16, y = 58, w = 500, h = 400 })
    t.eq({ x = 16, y = 58 }, c.top_left)
    t.eq({ x = 516, y = 58 }, c.top_right)
    t.eq({ x = 16, y = 458 }, c.bottom_left)
    t.eq({ x = 516, y = 458 }, c.bottom_right)
  end)
end)

t.describe("area.build: the published shape", function()
  t.it("carries the scene name, work's corners, and every column keyed by order", function()
    local out = area.build("code", { x = 0, y = 0, w = 1000, h = 800 }, {
      [1] = { x = 0, y = 0, w = 400, h = 800 },
      [2] = { x = 400, y = 0, w = 600, h = 800 },
    })
    t.eq("code", out.scene)
    t.eq({ x = 0, y = 0 }, out.work.top_left)
    t.eq({ x = 1000, y = 800 }, out.work.bottom_right)
    t.eq({ x = 0, y = 0 }, out.columns["1"].top_left)
    t.eq({ x = 1000, y = 800 }, out.columns["2"].bottom_right)
  end)

  t.it("publishes an empty columns map for a scene with no column boxes", function()
    local out = area.build("loose", { x = 0, y = 0, w = 1000, h = 800 })
    t.eq({}, out.columns)
  end)
end)
