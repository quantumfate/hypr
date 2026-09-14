-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- Holding windows a mode does not admit, and giving them back.
---
--- The failure this guards against is a window the user cannot reach and did
--- not close, so the record surviving a restart and never restoring a reused
--- address matter more than anything cosmetic here.
local t = require("tests.harness")

local function fresh(windows)
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  for _, mod in ipairs({ "hypr.lib.store", "hypr.hyprfocus.hold" }) do
    package.loaded[mod] = nil
  end

  -- The record is a file; stub the handle so these specs stay about holding
  -- rather than about JSON on disk.
  local saved = {}
  package.loaded["hypr.lib.store"] = {
    define = function()
      return {
        get = function(_, key)
          return key == "windows" and saved.windows or saved
        end,
        set = function(_, patch)
          for k, v in pairs(patch) do
            saved[k] = v
          end
        end,
      }
    end,
  }

  stub.get_windows = function()
    return windows or {}
  end
  return stub, require("hypr.hyprfocus.hold"), saved
end

local function win(address, workspace)
  return { address = address, workspace = { id = 1, name = workspace } }
end

local function moves(stub)
  local out = {}
  for _, d in ipairs(stub.dispatched) do
    if d.name == "dsp.window.move" then
      local a = d.args[1]
      out[#out + 1] = a.window .. "->" .. a.workspace
    end
  end
  return table.concat(out, " ")
end

t.describe("holding", function()
  t.it("parks every window on the workspace", function()
    local stub, hold = fresh({ win("0x1", "code"), win("0x2", "code"), win("0x9", "gaming") })
    t.eq(2, hold.hold("code"))
    t.eq("address:0x1->special:hyprfocus-held address:0x2->special:hyprfocus-held", moves(stub))
  end)

  t.it("does not take the user with it", function()
    -- A following move throws the user across the desk once per window.
    local stub, hold = fresh({ win("0x1", "code") })
    hold.hold("code")
    t.eq(false, stub.dispatched[1].args[1].follow)
  end)

  t.it("leaves other workspaces alone", function()
    local stub, hold = fresh({ win("0x9", "gaming") })
    t.eq(0, hold.hold("code"))
    t.eq("", moves(stub))
  end)

  t.it("records where each window came from", function()
    local _, hold = fresh({ win("0x1", "code") })
    hold.hold("code")
    t.eq("code", hold.origin("0x1"))
  end)

  t.it("does not hold a window twice", function()
    -- A second hold would overwrite the origin with the holding workspace and
    -- lose the way back.
    local stub, hold = fresh({ win("0x1", "code") })
    hold.hold("code")
    hold.hold("code")
    t.eq("code", hold.origin("0x1"), "the original workspace survived")
    t.eq(1, select(2, moves(stub):gsub("address:0x1", "")), "moved once")
  end)
end)

t.describe("restoring", function()
  t.it("puts windows back where they were", function()
    local stub, hold = fresh({ win("0x1", "code"), win("0x2", "code") })
    hold.hold("code")
    stub.dispatched = {}
    t.eq(2, hold.restore("code"))
    t.eq("address:0x1->name:code address:0x2->name:code", moves(stub))
  end)

  t.it("clears the record once they are back", function()
    local _, hold = fresh({ win("0x1", "code") })
    hold.hold("code")
    hold.restore("code")
    t.eq(nil, hold.origin("0x1"))
  end)

  t.it("leaves windows held from another workspace alone", function()
    local stub, hold = fresh({ win("0x1", "code"), win("0x9", "media") })
    hold.hold("code")
    hold.hold("media")
    stub.dispatched = {}
    hold.restore("code")
    t.eq("address:0x1->name:code", moves(stub))
    t.eq("media", hold.origin("0x9"), "the other workspace's window stays held")
  end)

  t.it("drops a window that died while held rather than moving a stranger", function()
    -- Addresses are reused. Restoring by an address that now belongs to
    -- something else would move an unrelated window onto the workspace.
    local stub, hold = fresh({ win("0x1", "code") })
    hold.hold("code")
    stub.get_windows = function()
      return {}
    end
    stub.dispatched = {}
    t.eq(0, hold.restore("code"))
    t.eq("", moves(stub))
    t.eq(nil, hold.origin("0x1"), "the dead record is gone")
  end)

  t.it("restoring a workspace that holds nothing is harmless", function()
    local stub, hold = fresh({})
    t.eq(0, hold.restore("code"))
    t.eq("", moves(stub))
  end)
end)

t.describe("the record", function()
  t.it("names every workspace with windows held from it", function()
    local _, hold = fresh({ win("0x1", "code"), win("0x9", "media") })
    hold.hold("code")
    hold.hold("media")
    local held = hold.workspaces()
    t.ok(held.code and held.media)
    t.eq(nil, held.gaming)
  end)

  t.it("survives being rebuilt from the store", function()
    -- A shell restart must not turn a held window into a lost one.
    local stub, hold = fresh({ win("0x1", "code") })
    hold.hold("code")
    package.loaded["hypr.hyprfocus.hold"] = nil
    local again = require("hypr.hyprfocus.hold")
    t.eq("code", again.origin("0x1"))
    t.ok(stub)
  end)

  t.it("can be abandoned when it no longer describes reality", function()
    local _, hold = fresh({ win("0x1", "code") })
    hold.hold("code")
    hold.forget()
    t.eq(nil, hold.origin("0x1"))
  end)
end)
