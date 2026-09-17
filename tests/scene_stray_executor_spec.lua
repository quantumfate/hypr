-- The stray-float executor (LEO-367): hypr/events/scene.lua's window.open/
-- window.move_to_workspace wiring around hypr/scene/strays.lua. These assert
-- end to end — a real `hl.dispatch` call against a stub shaped like the live
-- compositor, not just the pure decision `scene_strays_spec.lua` already
-- covers.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")
local hl_stub = require("tests.hl_stub")

local CAPTURE = {
  blocks = { { classes = { "OBS" }, order = 1 } },
  barred = { "steam_app_default" },
  strays = "float",
}

---A trace.lua stub recording every emitted record.
---@return table calls, table stub_module
local function trace_stub()
  local calls = {}
  return calls, {
    emit = function(record)
      calls[#calls + 1] = record
    end,
  }
end

---@return table calls, table stub, table[] windows
local function fresh_scene()
  local calls, trace_mod = trace_stub()
  package.loaded["hypr.lib.trace"] = trace_mod

  local stub = hl_stub.new()
  _G.hl = stub
  _G.config = { host = { workspaces = { workspace_specs = {} } } }

  local scenes = { capture = CAPTURE }
  package.loaded["hypr.lib.store"] = {
    define = function()
      return {
        get = function()
          return { base = { scenes = scenes } }
        end,
        put = function(_, doc)
          scenes = doc.base.scenes
        end,
      }
    end,
  }

  for _, mod in ipairs({ "hypr.lib.hypr", "hypr.scene.spec", "hypr.scene.strays", "hypr.events.scene" }) do
    package.loaded[mod] = nil
  end

  local windows = {}
  stub.get_windows = function()
    return windows
  end
  stub.get_active_workspace = function()
    return { id = 4, name = "capture" }
  end

  -- Simulates the spiked-live compositor: `window.float` flips the addressed
  -- window's own `floating` field synchronously, the same way `group.toggle`
  -- seeds a group in the group-executor spec.
  local dispatched = {}
  stub.dispatched = dispatched
  function stub.dispatch(action)
    dispatched[#dispatched + 1] = action
    if type(action) == "table" and action.name == "dsp.window.float" then
      local address = action.args[1] and action.args[1].window and action.args[1].window:match("^address:(.+)$")
      local w = address and stub.get_window("address:" .. address)
      if w then
        w.floating = true
      end
    end
  end

  require("hypr.events.scene")
  return calls, stub, windows
end

---@param windows table[]
---@param over table
---@return table
local function win(windows, over)
  local w = {
    address = over.address,
    class = over.class,
    workspace = { id = 4, name = over.ws or "capture" },
    floating = over.floating,
  }
  windows[#windows + 1] = w
  return w
end

---@param stub table
---@param w table
local function open(stub, w)
  for _, cb in ipairs(stub.event_handlers["window.open"] or {}) do
    cb(w)
  end
end

---@param stub table
---@param w table
local function moved(stub, w)
  for _, cb in ipairs(stub.event_handlers["window.move_to_workspace"] or {}) do
    cb(w)
  end
end

t.describe("stray executor", function()
  t.it("floats an unblocked window address-targeted, without touching focus", function()
    local calls, stub, windows = fresh_scene()
    local w = win(windows, { address = "0x1", class = "mpv" })
    open(stub, w)

    t.ok(w.floating, "the window ends up floating")

    local floated = {}
    for _, record in ipairs(calls) do
      if record.event == "stray_float" then
        floated[#floated + 1] = record
      end
    end
    t.eq(1, #floated, "exactly one stray_float record")
    t.eq("arrange", floated[1].stage)

    for _, action in ipairs(stub.dispatched) do
      t.ok(action.name ~= "dsp.focus", "the executor never dispatches focus")
    end
  end)

  t.it("leaves a block member tiled", function()
    local calls, stub, windows = fresh_scene()
    local w = win(windows, { address = "0x1", class = "OBS" })
    open(stub, w)
    t.eq(nil, w.floating)
    for _, record in ipairs(calls) do
      t.ok(record.event ~= "stray_float")
    end
  end)

  t.it("leaves a barred class tiled", function()
    local calls, stub, windows = fresh_scene()
    local w = win(windows, { address = "0x1", class = "steam_app_default" })
    open(stub, w)
    t.eq(nil, w.floating)
    for _, record in ipairs(calls) do
      t.ok(record.event ~= "stray_float")
    end
  end)

  t.it("floats a stray that arrives by moving into the scene's workspace", function()
    local calls, stub, windows = fresh_scene()
    local w = win(windows, { address = "0x1", class = "mpv" })
    moved(stub, w)
    t.ok(w.floating)
    local floated = {}
    for _, record in ipairs(calls) do
      if record.event == "stray_float" then
        floated[#floated + 1] = record
      end
    end
    t.eq(1, #floated)
  end)

  t.it("does not re-dispatch once the window is already floating", function()
    local _, stub, windows = fresh_scene()
    local w = win(windows, { address = "0x1", class = "mpv", floating = true })
    open(stub, w)
    for _, action in ipairs(stub.dispatched) do
      t.ok(action.name ~= "dsp.window.float", "already floating: nothing to dispatch")
    end
  end)
end)
