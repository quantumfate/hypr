-- Test fixtures stub the runtime: partial `hl` objects and lookups the type
-- system cannot prove non-nil. The stub shape is the contract under test.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- Which monitor a workspace key acts on: the SEAT's (`hypr/events/seat.lua`),
--- never the pointer's and never the compositor's mark -- both follow the
--- pointer on this desk, and a workspace key must act where the keyboard is.
local t = require("tests.harness")

local MONITORS = {
  { name = "DP-2", x = 0, y = 0, width = 2560, height = 1440, scale = 1 },
  { name = "DP-1", x = 2560, y = 0, width = 5120, height = 1440, scale = 1 },
  { name = "HDMI-A-1", x = 7680, y = 0, width = 800, height = 1280, scale = 1 },
}

---@param seat_on string? the monitor the seat is claimed onto
---@param cursor table? pointer position
---@param marked string? the compositor's focused-monitor mark
---@param ignored string[]?
---@return string?
local function output_for(seat_on, cursor, marked, ignored)
  for k in pairs(package.loaded) do
    if k == "hypr" or k:match("^hypr%.") then
      package.loaded[k] = nil
    end
  end
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  stub.get_monitors = function()
    return MONITORS
  end
  stub.get_cursor_pos = function()
    return cursor
  end
  stub.get_active_monitor = function()
    return marked and { name = marked } or nil
  end
  _G.config = { host = { primary_monitor = "DP-1", ignored_monitors = ignored } }
  require("hypr.events.seat").claim(seat_on)
  return require("hypr.lib.bind").focused_output()
end

t.describe("the output a workspace key acts on", function()
  t.it("is the seat's monitor, wherever the pointer and the mark are", function()
    t.eq("DP-2", output_for("DP-2", { x = 4000, y = 100 }, "DP-1"))
    t.eq("DP-1", output_for("DP-1", { x = 100, y = 100 }, "DP-2"))
  end)

  t.it("is the mark only before anything has claimed a seat (config load)", function()
    t.eq("DP-2", output_for(nil, nil, "DP-2"))
  end)

  t.it("never lands on an ignored monitor", function()
    local ignored = { "HDMI-A-1" }
    t.eq("DP-1", output_for("HDMI-A-1", { x = 7700, y = 100 }, "HDMI-A-1", ignored))
    t.eq("DP-2", output_for("DP-2", { x = 7700, y = 100 }, "HDMI-A-1", ignored))
  end)
end)
