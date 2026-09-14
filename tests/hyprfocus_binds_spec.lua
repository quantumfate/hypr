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

  -- The stub's `bind` records but returns nothing, so give it a handle the way
  -- the real API does.
  local created = {}
  stub.bind = function(key)
    local handle = { key = key, enabled = true }
    function handle:set_enabled(value)
      self.enabled = value
    end
    created[#created + 1] = handle
    return handle
  end
  stub.define_submap = function(name, fn)
    local _ = name
    fn()
  end

  binds.capture()
  return stub, binds, created
end

t.describe("capture", function()
  t.it("files a bare bind under root", function()
    local stub, binds = fresh()
    stub.bind("SUPER, t")
    t.eq(1, binds.size("root"))
  end)

  t.it("files a submap's binds under the submap", function()
    local stub, binds = fresh()
    stub.define_submap("dofus", function()
      stub.bind("1")
      stub.bind("2")
    end)
    t.eq(2, binds.size("dofus"))
    t.eq(0, binds.size("root"))
  end)

  t.it("attributes a nested submap to the tree it belongs to", function()
    -- Everything under `dofus` is the Dofus tree, not a tree per nesting level.
    -- Otherwise a mode would have to name every depth to admit one feature.
    local stub, binds = fresh()
    stub.define_submap("dofus", function()
      stub.bind("1")
      stub.define_submap("dofus-team", function()
        stub.bind("t")
      end)
    end)
    t.eq(2, binds.size("dofus"))
    t.eq(0, binds.size("dofus-team"))
  end)

  t.it("still returns the handle to its caller", function()
    -- The wrap must be invisible: callers keep whatever the real API gave them.
    local stub, _ = fresh()
    local handle = stub.bind("SUPER, k")
    t.ok(handle and handle.set_enabled, "the caller lost its handle")
  end)

  t.it("restores the submap stack when a submap body fails", function()
    -- A config error inside one submap must not silently reparent every bind
    -- defined after it.
    local stub, binds = fresh()
    pcall(stub.define_submap, "broken", function()
      error("boom")
    end)
    stub.bind("SUPER, t")
    t.eq(1, binds.size("root"), "a later bind still belongs to root")
  end)

  t.it("is idempotent, so a second call does not double-record", function()
    local stub, binds = fresh()
    binds.capture()
    stub.bind("SUPER, t")
    t.eq(1, binds.size("root"))
  end)
end)

t.describe("admission", function()
  local function loaded()
    local stub, binds = fresh()
    stub.bind("SUPER, t")
    for _, name in ipairs({ "dofus", "llm", "screencapture" }) do
      stub.define_submap(name, function()
        stub.bind("a")
      end)
    end
    return stub, binds
  end

  t.it("enables what is admitted and disables the rest", function()
    local _, binds = loaded()
    local disabled = binds.admit({ "dofus" })
    t.eq("llm,screencapture", table.concat(disabled, ","))
  end)

  t.it("never withholds root, whatever is asked", function()
    -- A desk with no leader key has no way back, including no way to reach the
    -- surface that would undo the mode that did it.
    local _, binds = loaded()
    local disabled = binds.admit({})
    for _, name in ipairs(disabled) do
      t.ok(name ~= "root", "root was disabled")
    end
  end)

  t.it("actually flips the handles", function()
    local stub, binds = fresh()
    local kept, dropped
    stub.define_submap("dofus", function()
      kept = stub.bind("1")
    end)
    stub.define_submap("llm", function()
      dropped = stub.bind("2")
    end)
    binds.admit({ "dofus" })
    t.eq(true, kept.enabled)
    t.eq(false, dropped.enabled)
  end)

  t.it("re-enables a tree a later mode admits", function()
    local stub, binds = fresh()
    local handle
    stub.define_submap("dofus", function()
      handle = stub.bind("1")
    end)
    binds.admit({})
    t.eq(false, handle.enabled)
    binds.admit({ "dofus" })
    t.eq(true, handle.enabled, "withholding is not permanent")
  end)

  t.it("survives a handle whose bind is already gone", function()
    -- One dead handle must not abort a transition and leave the rest of the
    -- desk half-applied.
    local stub, binds = fresh()
    stub.define_submap("dofus", function()
      local handle = stub.bind("1")
      handle.set_enabled = function()
        error("removed")
      end
    end)
    stub.define_submap("llm", function()
      stub.bind("2")
    end)
    local ok = pcall(binds.admit, { "llm" })
    t.ok(ok, "a dead handle aborted the whole admission")
  end)

  t.it("names every tree that holds a bind", function()
    local _, binds = loaded()
    t.eq("dofus,llm,root,screencapture", table.concat(binds.names(), ","))
  end)
end)
