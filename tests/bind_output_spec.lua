-- Test fixtures stub the runtime: partial `hl` objects and lookups the type
-- system cannot prove non-nil. The stub shape is the contract under test.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- Which monitor a workspace key acts on. Keyed off the POINTER, because a
--- workspace key that crosses monitors is the bug this pins: keyboard focus
--- and the pointer drift apart routinely, and only `mod+j`/`mod+k` are
--- allowed to change screen.
local t = require("tests.harness")

local MONITORS = {
  { name = "DP-2", x = 0, y = 0, width = 2560, height = 1440, scale = 1 },
  { name = "DP-1", x = 2560, y = 0, width = 5120, height = 1440, scale = 1 },
  { name = "HDMI-A-1", x = 7680, y = 0, width = 800, height = 1280, scale = 1 },
}

---@param cursor table? pointer position, or nil for a runtime without one
---@param active string? the monitor holding keyboard focus
---@param ignored string[]?
---@return string?
local function output_for(cursor, active, ignored)
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
    return active and { name = active } or nil
  end
  _G.config = { host = { primary_monitor = "DP-1", ignored_monitors = ignored } }
  return require("hypr.lib.bind").focused_output()
end

t.describe("the output a workspace key acts on", function()
  t.it("is the monitor under the pointer, even when focus is elsewhere", function()
    t.eq("DP-2", output_for({ x = 100, y = 100 }, "DP-1"))
    t.eq("DP-1", output_for({ x = 4000, y = 100 }, "DP-2"))
  end)

  t.it("falls back to the focused monitor when the pointer answers nothing", function()
    -- Off every output (a gap between them, a runtime that reports no
    -- position): the focused monitor is still a better answer than none.
    t.eq("DP-2", output_for(nil, "DP-2"))
    t.eq("DP-1", output_for({ x = 99999, y = 99999 }, "DP-1"))
  end)

  t.it("never lands on an ignored monitor, pointer or not", function()
    local ignored = { "HDMI-A-1" }
    -- Pointing AT the ignored panel: the key acts on the primary rather than
    -- taking the desk somewhere the host says it never goes.
    t.eq("DP-1", output_for({ x = 7700, y = 100 }, "HDMI-A-1", ignored))
    t.eq("DP-2", output_for({ x = 100, y = 100 }, "HDMI-A-1", ignored))
  end)
end)
