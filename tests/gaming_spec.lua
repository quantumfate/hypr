-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- gaming scene: the media browser lifecycle beside the Dofus group.
---
--- The engine holds address registries in module state, so every test gets a
--- fresh module + stub: run.lua resets package.loaded between specs but not
--- between tests inside one spec file.
local t = require("tests.harness")

_G.config = {
  apps = {
    media_scene = { cmd = "zen-twilight -P Media --name zen-gaming-media", class = "zen-gaming-media" },
  },
  host = {
    workspaces = {
      workspace_specs = { { workspace = "4", default_name = "gaming" } },
    },
  },
}

---A fresh stub with the engine (re)required into it, seeded from no windows.
local function fresh()
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  stub.get_windows = function()
    return {}
  end
  package.loaded["hypr.lib.hypr"] = nil
  package.loaded["hypr.events.gaming"] = nil
  require("hypr.events.gaming")
  return stub
end

local function emit(stub, event, w)
  local handlers = stub.event_handlers[event]
  handlers[#handlers](w)
end

local function count_dispatches(stub, name)
  local n = 0
  for _, d in ipairs(stub.dispatched) do
    if d.name == name then
      n = n + 1
    end
  end
  return n
end

local function last_dispatch_named(stub, name)
  for i = #stub.dispatched, 1, -1 do
    if stub.dispatched[i].name == name then
      return stub.dispatched[i]
    end
  end
  return nil
end

local function dofus_on(addr)
  return { workspace = { id = 4, name = "gaming" }, class = "Dofus.x64", address = addr }
end

local function media_on(addr)
  return { workspace = { id = 4, name = "gaming" }, class = "zen-gaming-media", address = addr }
end

local function media_on_other(addr)
  return { workspace = { id = 5, name = "media" }, class = "zen-gaming-media", address = addr }
end

t.describe("gaming scene media browser", function()
  t.it("spawns the media browser when the first Dofus window opens", function()
    local stub = fresh()
    emit(stub, "window.open", dofus_on("0xa1"))
    local spawn = last_dispatch_named(stub, "dsp.exec_cmd")
    t.ok(spawn, "expected an exec_cmd dispatch")
    t.eq("uwsm app -- zen-twilight -P Media --name zen-gaming-media", spawn.args[1])
  end)

  t.it("does not spawn a second browser while one is already open", function()
    local stub = fresh()
    emit(stub, "window.open", media_on("0xb1"))
    emit(stub, "window.open", dofus_on("0xa1"))
    t.eq(0, count_dispatches(stub, "dsp.exec_cmd"), "browser already present -- no spawn")
  end)

  t.it("does not spawn twice when Dofus clients open back to back", function()
    local stub = fresh()
    emit(stub, "window.open", dofus_on("0xa1"))
    emit(stub, "window.open", dofus_on("0xa2"))
    t.eq(1, count_dispatches(stub, "dsp.exec_cmd"))
  end)

  t.it("ignores a Dofus window that opens off the scene", function()
    local stub = fresh()
    emit(stub, "window.open", {
      workspace = { id = 2 },
      class = "Dofus.x64",
      address = "0xa9",
    })
    t.eq(0, count_dispatches(stub, "dsp.exec_cmd"), "off-scene Dofus is not the scene's business")
  end)

  t.it("the media workspace's own browser does not satisfy the scene", function()
    local stub = fresh()
    emit(stub, "window.open", media_on_other("0xb9"))
    emit(stub, "window.open", dofus_on("0xa1"))
    t.eq(1, count_dispatches(stub, "dsp.exec_cmd"), "browser on name:media is not the scene's browser")
  end)

  t.it("closes the browser when the last Dofus window leaves", function()
    local stub = fresh()
    emit(stub, "window.open", media_on("0xb1"))
    emit(stub, "window.open", dofus_on("0xa1"))
    emit(stub, "window.open", dofus_on("0xa2"))

    emit(stub, "window.close", { address = "0xa1" })
    t.eq(0, count_dispatches(stub, "dsp.window.close"), "one Dofus left -- browser stays")
    emit(stub, "window.close", { address = "0xa2" })
    local close = last_dispatch_named(stub, "dsp.window.close")
    t.ok(close, "expected a window.close dispatch")
    t.eq("address:0xb1", close.args[1].window)
  end)

  t.it("a browser closing on its own does not close Dofus windows", function()
    local stub = fresh()
    emit(stub, "window.open", media_on("0xb1"))
    emit(stub, "window.open", dofus_on("0xa1"))

    emit(stub, "window.close", { address = "0xb1" })
    t.eq(0, count_dispatches(stub, "dsp.window.close"), "user closed the browser -- respected")
  end)
end)
