-- The re-home executor (LEO-353): hypr/events/scene.lua's
-- window.open wiring around hypr/scene/home.lua and hypr/scene/strays.lua.
-- Covers the bug a claimed window opening on a `strays = "float"` scene
-- used to hit: floated as an unblocked stray, then re-homed while still
-- floating. `scene_home_spec.lua` covers the pure decision; this asserts
-- the dispatches end to end against a stub shaped like the live compositor.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")
local hl_stub = require("tests.hl_stub")

-- `obsidian-linear`-shaped: a float-strays scene that claims nothing named
-- "mail". `proton`-shaped: claims it. Both active in the same mode, the
-- same layout the live bug was verified against.
local OBSIDIAN = {
  blocks = { { classes = { "obsidian" }, order = 1 } },
  barred = {},
  strays = "float",
}
local PROTON = {
  blocks = { { classes = { "mail" }, order = 1 } },
  barred = {},
  strays = "slot",
}

---@return table calls, table stub, table[] windows
local function fresh_scene()
  local calls = {}
  package.loaded["hypr.lib.trace"] = {
    emit = function(record)
      calls[#calls + 1] = record
    end,
  }

  local stub = hl_stub.new()
  _G.hl = stub
  _G.config = { host = { workspaces = { workspace_specs = {} } } }

  local scenes = { ["obsidian-linear"] = OBSIDIAN, proton = PROTON }
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

  -- Both scenes admitted, as `work` admits obsidian-linear and proton
  -- together (docs/scenes.md "Work").
  package.loaded["hypr.hyprfocus"] = {
    applied_desk = function()
      return { scenes = { { name = "obsidian-linear" }, { name = "proton" } } }
    end,
    apply_bindings = function() end,
    active = function() end,
    replace = function() end,
    applying = function()
      return false
    end,
  }

  for _, mod in ipairs({
    "hypr.lib.hypr",
    "hypr.scene.spec",
    "hypr.scene.strays",
    "hypr.scene.home",
    "hypr.events.scene",
  }) do
    package.loaded[mod] = nil
  end

  local windows = {}
  stub.get_windows = function()
    return windows
  end
  stub.get_active_workspace = function()
    return { id = 4, name = "obsidian-linear" }
  end

  -- The float dispatch honors `action`, like the live compositor (spiked
  -- live in tests/e2e/hq): "on" sets floating, "off" clears it, no `action`
  -- toggles from false (the only case the pre-fix code dispatched).
  local dispatched = {}
  stub.dispatched = dispatched
  function stub.dispatch(action)
    dispatched[#dispatched + 1] = action
    if type(action) == "table" and action.name == "dsp.window.float" then
      local args = action.args[1] or {}
      local address = args.window and args.window:match("^address:(.+)$")
      local w = address and stub.get_window("address:" .. address)
      if w then
        if args.action == "off" then
          w.floating = false
        elseif args.action == "on" or args.action == nil then
          w.floating = true
        end
      end
    elseif type(action) == "table" and action.name == "dsp.window.move" then
      local args = action.args[1] or {}
      local address = args.window and args.window:match("^address:(.+)$")
      local ws = args.workspace and args.workspace:match("^name:(.+)$")
      local w = address and stub.get_window("address:" .. address)
      if w and ws then
        w.workspace = { id = 5, name = ws }
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
    workspace = { id = 4, name = over.ws },
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

t.describe("home executor", function()
  t.it("re-homes a claimed window straight to its scene, tiled, never floated on the way", function()
    local calls, stub, windows = fresh_scene()
    local w = win(windows, { address = "0x1", class = "mail", ws = "obsidian-linear" })
    open(stub, w)

    t.eq("proton", w.workspace.name)
    t.eq(nil, w.floating)

    for _, record in ipairs(calls) do
      t.ok(record.event ~= "stray_float", "the claimed window never took the stray-float path")
    end
  end)

  t.it("settles a float it arrives with when re-homing", function()
    local calls, stub, windows = fresh_scene()
    -- Simulates the race the bug hit: the window is already floating on the
    -- wrong (float-strays) workspace by the time this decision runs, e.g.
    -- stray-floated before its scene became active.
    local w = win(windows, { address = "0x1", class = "mail", ws = "obsidian-linear", floating = true })
    open(stub, w)

    t.eq("proton", w.workspace.name)
    t.eq(false, w.floating, "the inherited float is cleared on re-home")

    local settled
    for _, action in ipairs(stub.dispatched) do
      if action.name == "dsp.window.float" and action.args[1].action == "off" then
        settled = true
      end
    end
    t.ok(settled, "an explicit off, not a toggle, settles the window")
    t.eq(nil, calls[#calls] and calls[#calls].event == "stray_float" and true or nil)
  end)

  t.it("never floats a stray whose class another active scene claims", function()
    local _, stub, windows = fresh_scene()
    -- Opens on obsidian-linear (float-strays) but "mail" belongs to proton,
    -- also active. Before the fix, strays.decide floated it here because it
    -- only ever looked at its own workspace's blocks.
    local w = win(windows, { address = "0x1", class = "mail", ws = "obsidian-linear" })
    open(stub, w)
    t.eq(nil, w.floating)
  end)

  t.it("still floats a real stray on the same float-strays scene", function()
    local _, stub, windows = fresh_scene()
    local w = win(windows, { address = "0x1", class = "mpv", ws = "obsidian-linear" })
    open(stub, w)
    t.ok(w.floating, "an unclaimed class still floats")
  end)
end)
