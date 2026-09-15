-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- Binding trees: held by name, admitted per mode.
---
--- Getting this wrong is a desk with no working keys, so the safety rail —
--- root is never withheld — matters more than any other behaviour here.
local t = require("tests.harness")

local function fresh()
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  package.loaded["hypr.hyprfocus.binds"] = nil
  local binds = require("hypr.hyprfocus.binds")
  binds.reset()

  -- The stub records but returns nothing, so give it a handle the way the real
  -- API does.
  stub.bind = function(key)
    local handle = { key = key, enabled = true }
    function handle:set_enabled(value)
      self.enabled = value
    end
    return handle
  end
  stub.define_submap = function(_, fn)
    fn()
  end
  return stub, binds
end

t.describe("recording", function()
  t.it("files a bare bind under root", function()
    local _, binds = fresh()
    binds.bind("SUPER, t")
    t.eq(1, binds.size("root"))
  end)

  t.it("files a submap's binds under the submap", function()
    local _, binds = fresh()
    binds.submap("dofus", function()
      binds.bind("1")
      binds.bind("2")
    end)
    t.eq(2, binds.size("dofus"))
    t.eq(0, binds.size("root"))
  end)

  t.it("attributes a nested submap to the tree it belongs to", function()
    -- Everything under `dofus` is the Dofus tree, not a tree per nesting level.
    -- Otherwise a mode would have to name every depth to admit one feature.
    local _, binds = fresh()
    binds.submap("dofus", function()
      binds.bind("1")
      binds.submap("dofus-team", function()
        binds.bind("t")
      end)
    end)
    t.eq(2, binds.size("dofus"))
    t.eq(0, binds.size("dofus-team"))
  end)

  t.it("returns the handle to its caller", function()
    -- Recording must be invisible: callers keep whatever the real API gave.
    local _, binds = fresh()
    local handle = binds.bind("SUPER, k")
    t.ok(handle and handle.set_enabled, "the caller lost its handle")
  end)

  t.it("restores the nesting when a submap body fails", function()
    -- A config error inside one submap must not silently reparent every bind
    -- defined after it.
    local _, binds = fresh()
    pcall(binds.submap, "broken", function()
      error("boom")
    end)
    binds.bind("SUPER, t")
    t.eq(1, binds.size("root"), "a later bind still belongs to root")
  end)

  t.it("never assigns to the runtime's own table", function()
    -- `hl` is read-only in Hyprland: assigning to it raises at config load and
    -- takes down every module required after. Wrapping it was tried and cost a
    -- desk that would not start.
    local stub, binds = fresh()
    local original = stub.bind
    binds.bind("SUPER, t")
    t.eq(original, stub.bind, "the runtime's bind function was replaced")
  end)
end)

t.describe("admission", function()
  local function loaded()
    local stub, binds = fresh()
    binds.bind("SUPER, t")
    for _, name in ipairs({ "dofus", "llm", "screencapture", "modes" }) do
      binds.submap(name, function()
        binds.bind("a")
      end)
    end
    return stub, binds
  end

  t.it("withholds exactly what it is asked to", function()
    local _, binds = loaded()
    t.eq("llm", table.concat(binds.admit({ "llm" }), ","))
  end)

  t.it("leaves a tree the declaration never mentions alone", function()
    -- The mistake that trapped a desk: a tree missing from the declaration was
    -- read as one to remove, so every tree not hand-listed vanished — the
    -- terminal and the way back among them. A gap must cost less than that.
    local _, binds = loaded()
    binds.admit({ "llm" })
    t.eq(0, #binds.admit({}), "admitting nothing withheld something")
  end)

  t.it("never withholds root", function()
    local _, binds = loaded()
    local disabled = binds.admit({ "root", "llm" })
    for _, name in ipairs(disabled) do
      t.ok(name ~= "root", "root was disabled")
    end
  end)

  t.it("never withholds the modes tree", function()
    -- Withholding it leaves the exit behind the door it just locked: the only
    -- way out of a mode would be the key that mode removed.
    local _, binds = loaded()
    local disabled = binds.admit({ "modes", "llm" })
    for _, name in ipairs(disabled) do
      t.ok(name ~= "modes", "the way back out of a mode was removed")
    end
  end)

  t.it("actually flips the handles", function()
    local _, binds = fresh()
    local kept, dropped
    binds.submap("dofus", function()
      kept = binds.bind("1")
    end)
    binds.submap("llm", function()
      dropped = binds.bind("2")
    end)
    binds.admit({ "llm" })
    t.eq(true, kept.enabled)
    t.eq(false, dropped.enabled)
  end)

  t.it("re-enables a tree a later mode keeps", function()
    local _, binds = fresh()
    local handle
    binds.submap("dofus", function()
      handle = binds.bind("1")
    end)
    binds.admit({ "dofus" })
    t.eq(false, handle.enabled)
    binds.admit({})
    t.eq(true, handle.enabled, "withholding is not permanent")
  end)

  t.it("survives a handle whose bind is already gone", function()
    local _, binds = fresh()
    binds.submap("dofus", function()
      local handle = binds.bind("1")
      handle.set_enabled = function()
        error("removed")
      end
    end)
    binds.submap("llm", function()
      binds.bind("2")
    end)
    local ok = pcall(binds.admit, { "dofus" })
    t.ok(ok, "a dead handle aborted the whole admission")
  end)

  t.it("names every tree that holds a bind", function()
    local _, binds = loaded()
    t.eq("dofus,llm,modes,root,screencapture", table.concat(binds.names(), ","))
  end)
end)

t.describe("the registry's words (LEO-306/287)", function()
  t.it("a keystr trigger unwraps before the split mines the words", function()
    -- Requiring the binds module after a fresh load also loads its whichkey
    -- requirement, whose registry we read through serialize.
    package.loaded["hypr.hyprfocus.binds"] = nil
    local stub = require("tests.hl_stub").new()
    _G.hl = stub
    stub.bind = function(key)
      local handle = { key = key, enabled = true }
      function handle:set_enabled(_) end
      return handle
    end
    package.loaded["hypr.lib.whichkey"] = nil
    local wk = require("hypr.lib.whichkey")
    local binds = require("hypr.hyprfocus.binds")
    binds.reset()
    -- stack is at root during a plain require; a described bind lands
    -- in the reset node with its SPEAKING words, not the whole trigger.
    binds.bind("+SUPER+d+", function() end, { description = "A described bind" })
    local registry = wk.serialize()
    local items = registry["reset"] and registry["reset"].items or {}
    t.eq(1, #items)
    t.eq("d", items[1].key)
    t.eq("SUPER", items[1].mods[1])
  end)
end)
