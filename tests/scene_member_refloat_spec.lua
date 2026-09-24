-- The float reconciliation (drag artifact re-tiling): a block member of the
-- focused scene that is floating on its own workspace re-tiles on focus —
-- a drag made the compositor float it and nothing else would ever put it
-- back (no float event exists to hook; the layout has no float branch).
-- Deliberate floats (the SUPER+ALT+T toggle, armed via M.arm_float) and
-- non-members (strays/pip territory) are left alone.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")
local hl_stub = require("tests.hl_stub")

local SCENES = {
  capture = {
    blocks = {
      { classes = { "OBS" }, order = 1 },
      { classes = { "zen" }, order = 2 },
    },
    barred = {},
    strays = "float",
  },
}

local windows = {}

---@return table calls, table stub, table scenes
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

  local scenes = { capture = SCENES.capture }
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
local function win(_, over)
  local w = {
    address = over.address,
    class = over.class,
    floating = over.floating or false,
    tags = over.tags or {},
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
  for _, cb in ipairs(stub.event_handlers["window.active"] or {}) do
    cb(w)
  end
end

t.describe("the float reconciliation", function()
  t.it("re-tiles a dragged block member on focus, without a focus dance", function()
    local calls, stub = fresh_scene()
    local member = win(windows, { address = "0x1", class = "OBS", ws = "capture", floating = true })
    stub.get_active_workspace = function()
      return { name = "capture" }
    end

    activate(stub, member)

    local refloated = false
    for _, action in ipairs(stub.dispatched) do
      if action.name == "dsp.window.float" and action.args[1] and action.args[1].window == "address:0x1" then
        refloated = true
      end
    end
    t.ok(refloated, "the drag artifact re-tiles")
    local named = false
    for _, c in ipairs(calls) do
      if c.event == "member_refloat" then
        named = true
      end
    end
    t.ok(named, "the reconciliation names what it did")
  end)

  t.it("leaves a deliberately floated member alone", function()
    local _, stub = fresh_scene()
    local member = win(windows, { address = "0x1", class = "OBS", ws = "capture", floating = true })
    stub.get_active_workspace = function()
      return { name = "capture" }
    end
    require("hypr.events.scene").arm_float("0x1")

    activate(stub, member)

    for _, action in ipairs(stub.dispatched) do
      t.eq(false, action.name == "dsp.window.float", "a member the user floated on purpose is never touched")
    end
    -- Toggling it back off clears the mark.
    require("hypr.events.scene").disarm_float("0x1")
    activate(stub, member)
    local refloated = false
    for _, action in ipairs(stub.dispatched) do
      if action.name == "dsp.window.float" and action.args[1] and action.args[1].window == "address:0x1" then
        refloated = true
      end
    end
    t.ok(refloated, "and the disarm makes it reconcile again")
  end)

  t.it("never re-tiles a non-member, whatever its float", function()
    local _, stub = fresh_scene()
    local stray = win(windows, { address = "0x2", class = "Random", ws = "capture", floating = true })
    stub.get_active_workspace = function()
      return { name = "capture" }
    end

    activate(stub, stray)

    t.eq(0, #stub.dispatched, "strays and pip keep their float")
  end)
end)

return t
