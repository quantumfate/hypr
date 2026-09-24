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

local function win(address, workspace, class)
  return { address = address, class = class, workspace = { id = 1, name = workspace } }
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

  -- A deck scene hides the members its columns are not scrolled to on a
  -- special workspace of its own. Those windows belong to the scene without
  -- standing on it, and a hold that only swept the named workspace left them
  -- behind: the mode withdrew `code`, its visible windows were parked, and
  -- the hidden ones surfaced in a mode that never admitted them.
  t.it("takes the scene's deck-parked members with it", function()
    local spec_lib = require("hypr.scene.spec")
    local original = spec_lib.load
    spec_lib.load = function()
      return { code = { name = "code", blocks = { { classes = { "zen-twilight" }, order = 1 } } } }
    end
    local ok, err = pcall(function()
      local stub, hold = fresh({
        win("0x1", "code", "Kitty-Main"),
        win("0x2", "special:deck-hold", "zen-twilight"),
        win("0x3", "special:deck-hold", "Dofus.x64"),
      })
      t.eq(2, hold.hold("code"), "the tile on the workspace and the member parked off it")
      t.eq(true, moves(stub):find("address:0x2->special:hyprfocus-held", 1, true) ~= nil)
      t.eq(false, moves(stub):find("address:0x3", 1, true) ~= nil, "another scene's parked window stays put")
    end)
    spec_lib.load = original
    if not ok then
      error(err, 0)
    end
  end)

  -- A held window's origin records where it STOOD, not where it belongs. A
  -- declaration edited while it was held (a scene given its own browser
  -- profile) can leave that origin a workspace whose blocks no longer name
  -- the class: restoring it there put an undeclared window on a managed
  -- workspace, where the stray policy floated it -- a second browser sprawled
  -- across the scene that had just opened its own.
  t.it("restores a window to the scene that declares it today", function()
    local spec_lib = require("hypr.scene.spec")
    local original = spec_lib.load
    spec_lib.load = function()
      return { media = { name = "media", blocks = { { classes = { "zen-twilight-media" }, order = 1 } } } }
    end
    local ok, err = pcall(function()
      local stub, hold = fresh({ win("0x1", "dofus", "zen-twilight-media") })
      hold.hold("dofus")
      hold.restore("dofus")
      t.eq(true, moves(stub):find("address:0x1->name:media", 1, true) ~= nil, "not back to its stale origin")
    end)
    spec_lib.load = original
    if not ok then
      error(err, 0)
    end
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

  t.it("keeps the origin when a window is held twice", function()
    -- The compositor may still report the window on its workspace. Moving it
    -- to the holding place again is harmless; losing the way back is not.
    local _, hold = fresh({ win("0x1", "code") })
    hold.hold("code")
    hold.hold("code")
    t.eq("code", hold.origin("0x1"), "the original workspace survived")
  end)

  t.it("overwrites a stale record for a window that stands on the workspace", function()
    -- A reused address, or an entry an interrupted apply left behind, used to
    -- make hold skip the window; the workspace was then withdrawn under it.
    local stub, hold, saved = fresh({ win("0x1", "code") })
    saved.windows = { ["0x1"] = "obsidian-linear", ["0xdead"] = "code" }
    t.eq(1, hold.hold("code"))
    t.eq("address:0x1->special:hyprfocus-held", moves(stub))
    t.eq("code", hold.origin("0x1"))
    t.eq(nil, hold.origin("0xdead"), "dead addresses are pruned")
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

t.describe("shelf windows are never held (LEO-370)", function()
  local STEAM = { id = "steam", key = "t", class = "steam", launch = "steam", desc = "Steam", scenes = {} }

  -- Drawers are declared data now (LEO-363), read live off the store; a hold
  -- spec fixes the list by overriding `drawer.load` on the shared module
  -- table, which is the same one `hold.lua` captured at require time.
  ---@param drawers Drawer[]
  local function with_drawers(drawers, fn)
    local drawer = require("hypr.lib.drawer")
    local original = drawer.load
    drawer.load = function()
      return drawers
    end
    local ok, err = pcall(fn)
    drawer.load = original
    if not ok then
      error(err, 0)
    end
  end

  t.it("a shelf-classed window on the withdrawn workspace is left standing", function()
    with_drawers({ STEAM }, function()
      local stub, hold = fresh({ win("0x1", "code"), win("0x2", "code", "steam") })
      t.eq(1, hold.hold("code"), "only the non-shelf window is parked")
      t.eq("address:0x1->special:hyprfocus-held", moves(stub))
      t.eq(nil, hold.origin("0x2"))
    end)
  end)

  t.it("a window already on a shelf special workspace is left standing, class aside", function()
    with_drawers({}, function()
      local stub, hold = fresh({ win("0x1", "special:shelf-ankama") })
      t.eq(0, hold.hold("special:shelf-ankama"))
      t.eq("", moves(stub))
    end)
  end)
end)

t.describe("reachability invariant", function()
  local function w(address, workspace)
    return { address = address, workspace = workspace }
  end
  local known = { code = true, dofus = true, logs = true }

  t.it("accepts admitted, shelf, unmanaged and legitimately held windows", function()
    local _, hold = fresh()
    local out = hold.unreachable({
      w("0x1", "code"),
      w("0x2", "special:" .. "shelf-signal"),
      w("0x3", "2"),
      w("0x4", "special:hyprfocus-held"),
    }, { code = true }, known, { ["0x4"] = "dofus" })
    t.eq({}, out)
  end)

  t.it("names each violation", function()
    local _, hold = fresh()
    local out = hold.unreachable({
      w("0x1", "dofus"),
      w("0x2", "special:hyprfocus-held"),
      w("0x3", "special:hyprfocus-held"),
    }, { code = true }, known, { ["0x3"] = "code" })
    t.eq({ "withdrawn", "no_origin", "not_restored" }, { out[1].reason, out[2].reason, out[3].reason })
  end)

  t.it("projects dispatched moves over the reported workspace", function()
    local _, hold = fresh()
    local projected = hold.project({ win("0x1", "code"), win("0x2", "logs") }, { ["0x1"] = hold.HELD })
    t.eq("special:hyprfocus-held", projected[1].workspace)
    t.eq("logs", projected[2].workspace)
  end)
end)
