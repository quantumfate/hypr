-- The fullscreen reconciliation: a window that arrives maximized or
-- fullscreen on a scene whose design does not allow it is cleared on open
-- and on every focus (zen re-requests maximize after its surface is
-- remapped by a hold round trip). The gaming mode's scenes — where
-- fullscreen IS the design — and windows the user toggled deliberately are
-- never fought.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")
local hl_stub = require("tests.hl_stub")

local SCENES = {
  base = {
    scenes = {
      code = { blocks = { { classes = { "OBS" }, order = 1 } } },
      dofus = { blocks = { { classes = { "Dofus.x64" }, order = 1, group = true } } },
    },
  },
  modes = {
    gaming = { scenes = { { name = "dofus", monitor = "primary" } } },
    work = { scenes = { { name = "code", monitor = "primary" } } },
  },
}

local windows = {}

---@return table calls, table stub
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

  local scenes = { capture = SCENES.base.scenes }
  package.loaded["hypr.lib.store"] = {
    define = function(name)
      if name == "hyprfocus" then
        return {
          get = function()
            return { base = SCENES.base, modes = SCENES.modes }
          end,
          put = function() end,
        }
      end
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

  for _, mod in ipairs({
    "hypr.lib.hypr",
    "hypr.scene.spec",
    "hypr.scene.companion",
    "hypr.scene.identify",
    "hypr.scene.grouping",
    "hypr.scene.group_adapters",
    "hypr.scene.strays",
    "hypr.scene.home",
    "hypr.events.scene",
  }) do
    package.loaded[mod] = nil
  end

  windows = {}
  stub.get_windows = function()
    return windows
  end

  require("hypr.events.scene")
  return calls, stub
end

---@param over table
---@return table
local function win(over)
  local w = {
    address = over.address,
    class = over.class,
    floating = false,
    fullscreen = over.fullscreen or 0,
    fullscreenClient = over.fullscreenClient or 0,
    tags = {},
    workspace = { id = 7, name = over.ws },
  }
  windows[#windows + 1] = w
  return w
end

---@param stub table
---@param w table
local function activate(stub, w)
  stub.get_active_window = function()
    return w
  end
  stub.get_active_workspace = function()
    return { name = w.workspace.name }
  end
  for _, cb in ipairs(stub.event_handlers["window.active"] or {}) do
    cb(w)
  end
end

t.describe("the fullscreen reconciliation", function()
  t.it("clears a maximized window the moment it takes focus", function()
    local calls, stub = fresh_scene()
    local member = win({ address = "0x1", class = "OBS", ws = "code", fullscreen = 1 })
    stub.get_active_workspace = function()
      return { name = "code" }
    end

    activate(stub, member)

    local cleared = false
    for _, action in ipairs(stub.dispatched) do
      if action.name == "dsp.window.fullscreen" and action.args[1] and action.args[1].mode == "fullscreen" then
        cleared = true
      end
    end
    t.ok(cleared, "the maximized state does not survive focus")
    local named = false
    for _, c in ipairs(calls) do
      if c.event == "fullscreen_cleared" then
        named = true
      end
    end
    t.ok(named, "the reconciliation names what it did")
  end)

  t.it("never touches the gaming mode's scenes", function()
    local _, stub = fresh_scene()
    local game = win({ address = "0x2", class = "steam_app_default", ws = "dofus", fullscreen = 2 })

    activate(stub, game)

    for _, action in ipairs(stub.dispatched) do
      t.eq(false, action.name == "dsp.window.fullscreen", "fullscreen is the design on a gaming scene")
    end
  end)

  t.it("leaves a window the user maximized deliberately alone", function()
    local _, stub = fresh_scene()
    local member = win({ address = "0x1", class = "OBS", ws = "code", fullscreen = 2 })
    require("hypr.events.scene").arm_float("0x1")

    activate(stub, member)

    for _, action in ipairs(stub.dispatched) do
      t.eq(false, action.name == "dsp.window.fullscreen", "a deliberate maximize is user intent")
    end
    require("hypr.events.scene").disarm_float("0x1")
  end)

  t.it("is silent when the declaration is missing (fails open)", function()
    local _, stub = fresh_scene()
    stub.event_handlers = nil
    -- A fresh module over a store whose declaration read fails: the
    -- engine must not fight the desk, so nothing is cleared.
    local raw = {}
    stub.get_windows = function()
      return raw
    end
    local member = {
      address = "0x3",
      class = "OBS",
      fullscreen = 2,
      tags = {},
      workspace = { id = 1, name = "code" },
    }
    raw[1] = member
    stub.event_handlers = {}
    stub.event_handlers["window.active"] = {}
    -- re-require with a store that cannot answer, wired by replacing the module
    package.loaded["hypr.lib.store"] = {
      define = function()
        return {
          get = function()
            return {}
          end,
        }
      end,
    }
    package.loaded["hypr.events.scene"] = nil
    stub.event_handlers = {}
    require("hypr.events.scene")
    stub.get_active_window = function()
      return member
    end
    stub.get_active_workspace = function()
      return { name = "code" }
    end
    for _, cb in ipairs(stub.event_handlers["window.active"] or {}) do
      cb(member)
    end
    t.eq(0, #stub.dispatched, "no declaration, no enforcement")
  end)
end)

return t
