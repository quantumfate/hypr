-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- The scene engine end to end (LEO-245): events in, dispatches out.
---
--- The decisions themselves are covered by scene_model_spec; what is under
--- test here is everything the model deliberately does not know — when a pass
--- is allowed to run, which compositor call carries out an intent, and who
--- the scene considers its own.
local t = require("tests.harness")

local GAMING = {
  blocks = {
    { classes = { "Dofus.x64" }, group = true, order = 1, share = 0.67, collect = true },
    { classes = { "zen-gaming-media" }, order = 2, share = 0.33, guard = "deny" },
  },
  barred = { "steam_app_default" },
}

---The scenes document lives in the state store now; the stub hands it over
---the same shape the real store handle answers.
local function define_store(scenes)
  package.loaded["hypr.lib.store"] = {
    define = function()
      return {
        get = function()
          return { scenes = scenes }
        end,
        put = function(_, doc)
          scenes = doc.scenes
        end,
      }
    end,
  }
end

---A fake Hyprland group: `add`/`remove` mutate the fixture the way the real
---object API mutates the compositor, so a pass that groups windows changes
---what the next read sees.
local function new_group(world, key)
  local group = { key = key, members = {} }
  function group:add(w)
    if w.group then
      w.group:remove(w)
    end
    self.members[#self.members + 1] = w
    w.group = self
  end
  function group:remove(w)
    for i, member in ipairs(self.members) do
      if member == w then
        table.remove(self.members, i)
        break
      end
    end
    w.group = nil
    if #self.members <= 1 then
      for _, member in ipairs(self.members) do
        member.group = nil
      end
      self.members = {}
    end
  end
  world.groups[#world.groups + 1] = group
  return group
end

---@return table stub, table world
local function fresh(active)
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  _G.config = { host = { workspaces = { workspace_specs = {} } } }
  define_store({ gaming = GAMING })
  for _, mod in ipairs({
    "hypr.lib.hypr",
    "hypr.scene.spec",
    "hypr.scene.model",
    "hypr.scene.snapshot",
    "hypr.scene.registry",
    "hypr.scene.actuator",
    "hypr.scene.schedule",
    "hypr.events.scene",
  }) do
    package.loaded[mod] = nil
  end

  local world = { windows = {}, groups = {}, active = active or "gaming", layout = "lua:scene", focused = nil }
  stub.get_windows = function()
    return world.windows
  end
  stub.get_active_workspace = function()
    return { id = 4, name = world.active, tiled_layout = world.layout }
  end
  stub.get_active_window = function()
    return world.focused
  end
  stub.get_window = function(selector)
    local address = selector:match("^address:(.+)$")
    for _, w in ipairs(world.windows) do
      if w.address == address then
        return w
      end
    end
    return nil
  end
  world.group = function(key)
    return new_group(world, key)
  end

  -- The compositor's side of the two dispatchers the engine still needs:
  -- focus moves, and toggling a group on a lone window creates one. Without
  -- these the fixture would answer "nothing happened" to a correction that
  -- does in fact land, and the pass would look like an oscillation.
  local record = stub.dispatch
  stub.dispatch = function(action)
    record(action)
    if action.name == "dsp.focus" then
      local selector = action.args[1] and action.args[1].window
      local address = selector and selector:match("^address:(.+)$")
      world.focused = address and stub.get_window("address:" .. address) or world.focused
    elseif action.name == "dsp.group.toggle" and world.focused then
      local w = world.focused
      if w.group then
        w.group:remove(w)
      else
        world.group("toggled"):add(w)
      end
    end
  end
  return stub, world
end

local function win(world, over)
  local w = {
    address = over.address,
    class = over.class,
    workspace = { id = over.ws_id or 4, name = over.ws or "gaming" },
    floating = over.floating or false,
    at = { x = over.x or 0, y = 0 },
    size = { x = over.w or 1000, y = 1000 },
  }
  world.windows[#world.windows + 1] = w
  return w
end

local function emit(stub, event, w)
  for _, cb in ipairs(stub.event_handlers[event] or {}) do
    cb(w)
  end
end

---Run pending timers until the engine goes quiet, bounded so a runaway chain
---fails the test instead of hanging the suite.
local function drain(stub)
  local flushed = 0
  for _ = 1, 200 do
    if flushed >= #stub.timers then
      return true
    end
    local upto = #stub.timers
    for i = flushed + 1, upto do
      stub.timers[i].cb()
    end
    flushed = upto
  end
  return false
end

local function named(stub, name)
  local out = {}
  for _, d in ipairs(stub.dispatched) do
    if d.name == name then
      out[#out + 1] = d
    end
  end
  return out
end

t.describe("visibility", function()
  t.it("dispatches nothing while its workspace is behind the user", function()
    -- The regression this pins: corrections reach a hidden workspace only by
    -- focusing a window on it, which carries the user there and fires
    -- workspace.active, which arms the next scene. One workspace switch used
    -- to set the whole desk off.
    local stub, world = fresh("code")
    local a = win(world, { address = "0x1", class = "Dofus.x64" })
    win(world, { address = "0x2", class = "Dofus.x64", x = 500 })
    require("hypr.events.scene")
    emit(stub, "window.open", a)
    t.ok(drain(stub), "the engine settled")
    t.eq(0, #stub.dispatched, "nothing dispatched for a scene the user cannot see")
  end)

  t.it("realizes the scene when the user arrives on it", function()
    local stub, world = fresh("code")
    local a = win(world, { address = "0x1", class = "Dofus.x64" })
    win(world, { address = "0x2", class = "Dofus.x64", x = 500 })
    require("hypr.events.scene")
    emit(stub, "window.open", a)
    drain(stub)

    world.active = "gaming"
    emit(stub, "workspace.active", nil)
    t.ok(drain(stub), "the engine settled")
    t.ok(a.group, "the block was grouped on arrival")
    t.eq(2, #a.group.members)
  end)

  t.it("stops mid-pass if the user leaves", function()
    local stub, world = fresh("gaming")
    local a = win(world, { address = "0x1", class = "Dofus.x64" })
    win(world, { address = "0x2", class = "Dofus.x64", x = 500 })
    require("hypr.events.scene")
    emit(stub, "window.open", a)
    world.active = "code"
    t.ok(drain(stub), "the engine settled")
    t.eq(0, #stub.dispatched)
  end)

  t.it("asks for nothing on a workspace running another layout", function()
    -- The scene is the layout. A workspace the user cycled to master keeps
    -- its groups' static rules (compile.lua emits those for any layout) but
    -- the engine no longer rearranges anything: corrections aimed at
    -- another layout's output are the fight that was retired.
    local stub, world = fresh()
    world.layout = "master"
    local a = win(world, { address = "0x1", class = "Dofus.x64" })
    win(world, { address = "0x2", class = "Dofus.x64", x = 500 })
    require("hypr.events.scene")
    emit(stub, "window.open", a)
    t.ok(drain(stub), "the engine settled")
    t.eq(0, #stub.dispatched, "no join was ever dispatched onto master")
  end)

  t.it("resumes arrange on a workspace cycled back to the scene layout", function()
    local stub, world = fresh()
    world.layout = "dwindle"
    local a = win(world, { address = "0x1", class = "Dofus.x64" })
    local b = win(world, { address = "0x2", class = "Dofus.x64", x = 500 })
    require("hypr.events.scene")
    emit(stub, "window.open", a)
    t.ok(drain(stub))
    t.eq(nil, a.group, "the engine did not group under dwindle")

    world.layout = "lua:scene"
    emit(stub, "workspace.active", nil)
    t.ok(drain(stub), "the engine settled")
    t.ok(a.group and a.group == b.group, "the block was grouped again on the scene layout")
  end)
end)

t.describe("grouping", function()
  t.it("joins through the group object, not a hop chain", function()
    -- `HL.Group:add` names the window it acts on. The movewindow/moveintogroup
    -- dance it replaced could only reach the window beside the group, so it
    -- walked one tile at a time — and every hop was a visible jump.
    local stub, world = fresh()
    local a = win(world, { address = "0x1", class = "Dofus.x64" })
    local b = win(world, { address = "0x2", class = "Dofus.x64", x = 500 })
    require("hypr.events.scene")
    emit(stub, "window.open", a)
    t.ok(drain(stub))
    t.ok(a.group and a.group == b.group, "both clients share one group")
    t.eq(0, #named(stub, "dsp.window.move"), "no positional hops were needed")
  end)

  t.it("converges a block that split into two groups", function()
    local stub, world = fresh()
    local a = win(world, { address = "0x1", class = "Dofus.x64" })
    local b = win(world, { address = "0x2", class = "Dofus.x64", x = 300 })
    local c = win(world, { address = "0x3", class = "Dofus.x64", x = 600 })
    local major, minor = world.group("major"), world.group("minor")
    major:add(a)
    major:add(b)
    minor:add(c)
    require("hypr.events.scene")
    emit(stub, "window.open", c)
    t.ok(drain(stub))
    t.eq(3, #a.group.members, "the minority group folded into the majority")
  end)

  t.it("ejects a window auto_group swallowed", function()
    local stub, world = fresh()
    local a = win(world, { address = "0x1", class = "Dofus.x64" })
    local b = win(world, { address = "0x2", class = "Dofus.x64", x = 300 })
    local foreign = win(world, { address = "0x9", class = "zen-gaming-media", x = 600 })
    local g = world.group("g")
    g:add(a)
    g:add(b)
    g:add(foreign)
    require("hypr.events.scene")
    emit(stub, "window.open", foreign)
    t.ok(drain(stub))
    t.eq(nil, foreign.group, "the browser is a tile of its own again")
    t.eq(2, #a.group.members)
  end)
end)

t.describe("collection", function()
  t.it("moves a drifted member home without taking the user with it", function()
    local stub, world = fresh()
    local a = win(world, { address = "0x1", class = "Dofus.x64" })
    local stray = win(world, { address = "0x7", class = "Dofus.x64", ws = "code", ws_id = 2 })
    require("hypr.events.scene")
    -- The stray was the scene's before it wandered: it opened there.
    emit(stub, "window.open", a)
    stray.workspace = { id = 4, name = "gaming" }
    emit(stub, "window.open", stray)
    stray.workspace = { id = 2, name = "code" }
    drain(stub)
    world.active = "gaming"
    emit(stub, "workspace.active", nil)
    drain(stub)

    local moves = named(stub, "dsp.window.move")
    t.ok(#moves > 0, "the stray was moved")
    local args = moves[1].args[1]
    t.eq("address:0x7", args.window)
    t.eq("name:gaming", args.workspace)
    t.eq(false, args.follow, "a following move drags the user to the destination")
  end)

  t.it("leaves a matching window the scene never received", function()
    local stub, world = fresh()
    local a = win(world, { address = "0x1", class = "Dofus.x64" })
    win(world, { address = "0x7", class = "Dofus.x64", ws = "code", ws_id = 2 })
    require("hypr.events.scene")
    emit(stub, "window.open", a)
    t.ok(drain(stub))
    t.eq(0, #named(stub, "dsp.window.move"))
  end)

  t.it("forgets a window that closed", function()
    local stub, world = fresh()
    local a = win(world, { address = "0x1", class = "Dofus.x64" })
    require("hypr.events.scene")
    emit(stub, "window.open", a)
    drain(stub)
    emit(stub, "window.close", a)
    table.remove(world.windows, 1)
    win(world, { address = "0x1", class = "Dofus.x64", ws = "code", ws_id = 2 })
    win(world, { address = "0x2", class = "Dofus.x64" })
    emit(stub, "window.open", world.windows[2])
    t.ok(drain(stub))
    t.eq(0, #named(stub, "dsp.window.move"), "a closed address is not owned by its reuse")
  end)
end)

t.describe("termination", function()
  t.it("settles instead of oscillating when a correction does not take", function()
    -- A compositor that refuses a correction (a resize the layout will not
    -- honor) must end the pass, not re-issue it forever.
    local stub, world = fresh()
    win(world, { address = "0x1", class = "Dofus.x64", x = 0, w = 500 })
    local b = win(world, { address = "0x9", class = "zen-gaming-media", x = 500, w = 500 })
    require("hypr.events.scene")
    emit(stub, "window.open", b)
    t.ok(drain(stub), "the engine settled rather than looping")
    t.ok(#named(stub, "dsp.window.resize") <= 2, "the ignored resize was not retried forever")
  end)
end)

t.describe("public surface", function()
  t.it("names the scene on a workspace it owns", function()
    local stub = fresh()
    local M = require("hypr.events.scene")
    t.eq("gaming", M.active({ id = 4, name = "gaming" }))
    t.eq(nil, M.active({ id = 2, name = "code" }))
    t.eq(nil, M.active(nil))
    t.ok(stub)
  end)

  t.it("returns a block's leftmost tile", function()
    local stub, world = fresh()
    win(world, { address = "0x2", class = "Dofus.x64", x = 500 })
    win(world, { address = "0x1", class = "Dofus.x64", x = 0 })
    local M = require("hypr.events.scene")
    t.eq("0x1", M.tile("gaming", { class = "Dofus.x64" }).address)
    t.eq("0x1", M.tile("gaming", "Dofus.x64").address)
    t.eq(nil, M.tile("gaming", "org.kde.kdenlive"))
    t.ok(stub)
  end)
end)

t.describe("compiled rules", function()
  t.it("declares grouping once, from the scene", function()
    local stub = fresh()
    require("hypr.scene.compile").emit(require("hypr.scene.spec").load())
    local by_class = {}
    for _, rule in ipairs(stub.window_rules) do
      by_class[rule.match.class] = rule.group
    end
    t.eq("set always", by_class["Dofus.x64"])
    t.eq("deny", by_class["zen-gaming-media"], "the block's own guard, not the default bar")
    t.eq("barred", by_class["steam_app_default"])
  end)
end)
