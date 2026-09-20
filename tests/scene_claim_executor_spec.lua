-- The launch-claim executor (LEO-412): a spawned or surface-launched window
-- maps wherever the shared profile's static rule pins it (media), and
-- hypr/events/scene.lua's claim_launched step stamps the scene slot an armed
-- intent asked for, then the home step re-homes the claimed window.
-- scene_identify_executor_spec.lua covers the arrival-order slot stamp; this
-- covers the intent-armed, pinned-elsewhere path and the home move it
-- unlocks, against a stub shaped like the live compositor.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")
local hl_stub = require("tests.hl_stub")

local POKEMON = {
  blocks = {
    { classes = { "com.libretro.RetroArch" }, order = 1 },
    { classes = { "zen-twilight-media" }, order = 2, slot = "pokemon/chat", guard = "deny" },
    { classes = { "zen-twilight-media" }, order = 3, slot = "pokemon/stream", guard = "deny" },
  },
}
local MEDIA = {
  blocks = { { classes = { "mpv", "firefox", "zen-twilight-media" }, order = 1 } },
}
local DOFUS = {
  blocks = {
    { classes = { "Dofus.x64" }, order = 1 },
    { classes = { "zen-twilight-media" }, order = 2, slot = "dofus/browser", guard = "deny" },
  },
}

---@return table calls, table stub, table[] windows, table events
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

  local scenes = { pokemon = POKEMON, media = MEDIA, dofus = DOFUS }
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

  -- All three co-active, as gaming mode admits them (docs/scenes.md).
  package.loaded["hypr.hyprfocus"] = {
    applied_desk = function()
      return { scenes = { { name = "dofus" }, { name = "pokemon" }, { name = "media" } } }
    end,
    apply_bindings = function() end,
    active = function() end,
    replace = function() end,
  }

  for _, mod in ipairs({
    "hypr.lib.hypr",
    "hypr.scene.spec",
    "hypr.scene.identify",
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
    return { id = 4, name = "media" }
  end

  -- The tag dispatch lands synchronously, like the live compositor (spiked
  -- live, LEO-364); the move dispatch updates the window's workspace so a
  -- later pass sees the claimed window on its scene.
  local dispatched = {}
  stub.dispatched = dispatched
  function stub.dispatch(action)
    dispatched[#dispatched + 1] = action
    if type(action) == "table" then
      local args = action.args[1] or {}
      local address = args.window and args.window:match("^address:(.+)$")
      local w = address and stub.get_window("address:" .. address)
      if action.name == "dsp.window.tag" then
        local added = args.tag and args.tag:match("^%+(.+)$")
        if w and added then
          w.tags = w.tags or {}
          w.tags[#w.tags + 1] = added
        end
      elseif action.name == "dsp.window.move" then
        local ws = args.workspace and args.workspace:match("^name:(.+)$")
        if w and ws then
          w.workspace = { id = 5, name = ws }
        end
      end
    end
  end

  local events = require("hypr.events.scene")
  return calls, stub, windows, events
end

---@param windows table[]
---@param over table
---@return table
local function win(windows, over)
  local w = {
    address = over.address,
    class = over.class,
    tags = over.tags,
    workspace = { id = 4, name = over.ws },
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

---@param calls table[]
---@param event string
---@return boolean
local function has_event(calls, event)
  for _, record in ipairs(calls) do
    if record.event == event then
      return true
    end
  end
  return false
end

t.describe("launch-claim executor", function()
  t.it("claims an armed launch wherever the profile pinned it, slot + home", function()
    local calls, stub, windows, events = fresh_scene()
    events.arm_launch("pokemon", "zen-twilight-media")
    local w = win(windows, { address = "0x1", class = "zen-twilight-media", ws = "media" })
    open(stub, w)

    t.eq({ "slot:pokemon/chat" }, w.tags, "the intent's scene slot is stamped")
    t.eq("pokemon", w.workspace.name, "home moved the claimed window to its scene")
    t.ok(has_event(calls, "launch_claimed"), "the claim is decision-recorded")
  end)

  t.it("leaves a hand-opened window with no armed intent untouched", function()
    local calls, stub, windows, _ = fresh_scene()
    local w = win(windows, { address = "0x1", class = "zen-twilight-media", ws = "media" })
    open(stub, w)

    t.eq(nil, w.tags, "no slot stamp for an unclaimed window")
    t.eq("media", w.workspace.name, "stays on the pinned workspace")
    t.ok(not has_event(calls, "launch_claimed"), "no claim recorded")
  end)

  t.it("settles N rapid arms with N windows, one slot each", function()
    local _, stub, windows, events = fresh_scene()
    events.arm_launch("pokemon", "zen-twilight-media")
    events.arm_launch("pokemon", "zen-twilight-media")
    local a = win(windows, { address = "0x1", class = "zen-twilight-media", ws = "media" })
    open(stub, a)
    -- The second intent survives the first open's claim: the next same-class
    -- window is settled by it without a new arm.
    local b = win(windows, { address = "0x2", class = "zen-twilight-media", ws = "media" })
    open(stub, b)

    t.eq({ "slot:pokemon/chat" }, a.tags, "first armed window takes the first slot")
    t.eq({ "slot:pokemon/stream" }, b.tags, "second armed window takes the next slot")
    t.eq("pokemon", a.workspace.name)
    t.eq("pokemon", b.workspace.name)
  end)

  t.it("stamps the dofus scene's slot for a spawn-shaped intent", function()
    local calls, stub, windows, events = fresh_scene()
    events.arm_launch("dofus", "zen-twilight-media")
    local w = win(windows, { address = "0x1", class = "zen-twilight-media", ws = "media" })
    open(stub, w)

    t.eq({ "slot:dofus/browser" }, w.tags)
    t.eq("dofus", w.workspace.name)
    t.ok(has_event(calls, "launch_claimed"))
  end)

  t.it("settles one open with at most one intent, in sorted key order", function()
    -- dofus < pokemon in key sort: a shared-profile window opening while both
    -- intents are armed settles the dofus intent, and the pokemon intent
    -- stays armed for the window that will follow.
    local _, stub, windows, events = fresh_scene()
    events.arm_launch("pokemon", "zen-twilight-media")
    events.arm_launch("dofus", "zen-twilight-media")
    local a = win(windows, { address = "0x1", class = "zen-twilight-media", ws = "media" })
    open(stub, a)

    t.eq({ "slot:dofus/browser" }, a.tags, "the first-sorted intent claims the shared open")
    t.eq("dofus", a.workspace.name)

    local b = win(windows, { address = "0x2", class = "zen-twilight-media", ws = "media" })
    open(stub, b)
    t.eq({ "slot:pokemon/chat" }, b.tags, "the surviving pokemon intent settles the next window")
    t.eq("pokemon", b.workspace.name)
  end)
end)
