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

---Run every pending oneshot timer (the merge is deferred for a settle delay,
---so the spec has to fire it explicitly to exercise the scheduling).
local function settle(stub)
  for _, handle in ipairs(stub.timers) do
    handle.cb()
  end
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
  return { workspace = { id = 4 }, class = "Dofus.x64", address = addr }
end

local function media_on(addr)
  return { workspace = { id = 4 }, class = "zen-gaming-media", address = addr }
end

local function media_on_other(addr)
  return { workspace = { id = 5 }, class = "zen-gaming-media", address = addr }
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

---A live window as `hl.get_windows()` returns it after the settle delay.
local function dofus_live(addr, at, size)
  return { address = addr, class = "Dofus.x64", at = at, size = size }
end

t.describe("gaming scene group merge", function()
  t.it("folds a second Dofus window into the existing group", function()
    local stub = fresh()
    emit(stub, "window.open", dofus_on("0xa1"))
    emit(stub, "window.open", dofus_on("0xa2"))

    local a1 = dofus_live("0xa1", { x = 0, y = 0 }, { x = 800, y = 600 })
    local a2 = dofus_live("0xa2", { x = 800, y = 0 }, { x = 800, y = 600 })
    stub.get_windows = function()
      return { a1, a2 }
    end

    settle(stub)

    local merge = last_dispatch_named(stub, "dsp.window.move")
    t.ok(merge, "expected a window.move dispatch")
    t.eq("l", merge.args[1].into_group, "the existing group sits to the left of the new window")
    t.eq("address:0xa2", merge.args[1].window, "aims the merge at the new window by address")
  end)

  t.it("skips the merge when the new window is already a group member", function()
    local stub = fresh()
    emit(stub, "window.open", dofus_on("0xa1"))
    emit(stub, "window.open", dofus_on("0xa2"))

    local a1 = dofus_live("0xa1", { x = 0, y = 0 }, { x = 800, y = 600 })
    local a2 = dofus_live("0xa2", { x = 800, y = 0 }, { x = 800, y = 600 })
    a2.group = { members = { a1, a2 } }
    stub.get_windows = function()
      return { a1, a2 }
    end

    settle(stub)
    t.eq(0, count_dispatches(stub, "dsp.window.move"), "already grouped -- nothing to merge")
  end)

  t.it("does not schedule a merge for the first Dofus window", function()
    local stub = fresh()
    emit(stub, "window.open", dofus_on("0xa1"))
    t.eq(0, #stub.timers, "no existing member to aim at")
  end)

  t.it("skips the merge if the existing member closed before settling", function()
    local stub = fresh()
    emit(stub, "window.open", dofus_on("0xa1"))
    emit(stub, "window.open", dofus_on("0xa2"))

    -- The group's only member closed within the settle window; only the new
    -- window is still alive when the merge runs.
    stub.get_windows = function()
      return { dofus_live("0xa2", { x = 800, y = 0 }, { x = 800, y = 600 }) }
    end

    settle(stub)
    t.eq(0, count_dispatches(stub, "dsp.window.move"), "no live member to merge into")
  end)

  t.it("aims at the nearest existing member for the direction", function()
    local stub = fresh()
    emit(stub, "window.open", dofus_on("0xa1"))
    emit(stub, "window.open", dofus_on("0xa2"))
    emit(stub, "window.open", dofus_on("0xa3"))

    local a1 = dofus_live("0xa1", { x = 0, y = 0 }, { x = 800, y = 600 }) -- center (400,  300)
    local a2 = dofus_live("0xa2", { x = 800, y = 0 }, { x = 800, y = 600 }) -- center (1200, 300)
    local a3 = dofus_live("0xa3", { x = 1200, y = 600 }, { x = 800, y = 600 }) -- center (1600, 900)
    stub.get_windows = function()
      return { a1, a2, a3 }
    end

    settle(stub)

    -- The last merge (a3's) folds into whichever member is nearest. a2 is
    -- closest (721 < 1341); picking the far member a1 instead would resolve
    -- to "l", so this pins the nearest-member choice.
    local merge = last_dispatch_named(stub, "dsp.window.move")
    t.ok(merge, "expected a window.move dispatch")
    t.eq("u", merge.args[1].into_group, "the nearest member sits above the new window")
    t.eq("address:0xa3", merge.args[1].window)
  end)
end)
