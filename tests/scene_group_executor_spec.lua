-- The group executor (LEO-369): hypr/events/scene.lua's window.open/
-- window.move_to_workspace wiring around hypr/scene/grouping.lua. These
-- assert end to end — real `hl.dispatch`/`HL.Group` calls against a stub
-- shaped like the live compositor (tests/hl_stub.lua's `new_group`), not
-- just the pure decision `scene_grouping_spec.lua` already covers.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")
local hl_stub = require("tests.hl_stub")

local GAMING = {
  blocks = {
    { classes = { "Dofus.x64" }, group = true, order = 1 },
    { classes = { "zen-gaming-media" }, order = 2, guard = "deny" },
  },
  barred = { "steam_app_default" },
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

  local scenes = { gaming = GAMING }
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

  for _, mod in ipairs({ "hypr.lib.hypr", "hypr.scene.spec", "hypr.scene.grouping", "hypr.events.scene" }) do
    package.loaded[mod] = nil
  end

  local windows = {}
  stub.get_windows = function()
    return windows
  end
  stub.get_active_workspace = function()
    return { id = 4, name = "gaming" }
  end

  -- Simulates the spiked-live compositor: `group.toggle` seeds a real group
  -- on the addressed window synchronously (docs/scenes.md "Group"). A stub
  -- that only recorded the dispatch, like the default, would make the
  -- executor's own `hl.get_window(...).group` read see nothing.
  local dispatched = {}
  stub.dispatched = dispatched
  function stub.dispatch(action)
    dispatched[#dispatched + 1] = action
    if type(action) == "table" and action.name == "dsp.group.toggle" then
      local address = action.args[1] and action.args[1].window and action.args[1].window:match("^address:(.+)$")
      local w = address and stub.get_window("address:" .. address)
      if w and not w.group then
        hl_stub.new_group({ w })
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
  local w = { address = over.address, class = over.class, workspace = { id = 4, name = over.ws or "gaming" } }
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

t.describe("group executor", function()
  t.it("seeds a group when a second block window opens, without touching focus", function()
    local calls, stub, windows = fresh_scene()
    local a = win(windows, { address = "0x1", class = "Dofus.x64" })
    local b = win(windows, { address = "0x2", class = "Dofus.x64" })
    open(stub, b)

    t.ok(a.group, "first window ends up grouped")
    t.ok(b.group, "second window ends up grouped")
    t.eq(a.group, b.group, "both windows share the same group")

    local seeded = {}
    for _, record in ipairs(calls) do
      if record.event == "group_seed" then
        seeded[#seeded + 1] = record
      end
    end
    t.eq(1, #seeded, "exactly one group_seed record")
    t.eq("arrange", seeded[1].stage)

    for _, action in ipairs(stub.dispatched) do
      t.ok(action.name ~= "dsp.focus", "the executor never dispatches focus")
    end
  end)

  t.it("joins a third window into the existing group", function()
    local calls, stub, windows = fresh_scene()
    local a = win(windows, { address = "0x1", class = "Dofus.x64" })
    local b = win(windows, { address = "0x2", class = "Dofus.x64" })
    hl_stub.new_group({ a, b })
    local c = win(windows, { address = "0x3", class = "Dofus.x64" })

    open(stub, c)

    t.eq(a.group, c.group, "the third window joins the existing group")
    t.eq(3, #a.group.members)

    local joined = {}
    for _, record in ipairs(calls) do
      if record.event == "group_join" then
        joined[#joined + 1] = record
      end
    end
    t.eq(1, #joined)
  end)

  t.it("ejects a foreign window auto_group swallowed into the block's group", function()
    local calls, stub, windows = fresh_scene()
    local a = win(windows, { address = "0x1", class = "Dofus.x64" })
    local foreign = win(windows, { address = "0x9", class = "steam_app_default" })
    hl_stub.new_group({ a, foreign })
    t.ok(foreign.group, "the swallow already happened before this event")

    open(stub, foreign)

    t.eq(nil, foreign.group, "ejected")
    t.eq(1, #a.group.members, "the block's group keeps only its own member")

    local ejected = {}
    for _, record in ipairs(calls) do
      if record.event == "group_eject" then
        ejected[#ejected + 1] = record
      end
    end
    t.eq(1, #ejected)
  end)

  t.it("seeds a group in the class adapter's order, not open order", function()
    local _, stub, windows = fresh_scene()
    local group_adapters = require("hypr.scene.group_adapters")
    local saved = group_adapters.registry["Dofus.x64"]
    -- A test-double adapter standing in for the roster: deliberately the
    -- reverse of address order, so a pass that still just appended in
    -- `decision.members` order (address order) would be caught.
    group_adapters.registry["Dofus.x64"] = {
      order = function(members)
        local addrs = {}
        for _, m in ipairs(members) do
          addrs[#addrs + 1] = m.address
        end
        table.sort(addrs, function(x, y)
          return x > y
        end)
        return addrs
      end,
      enter = saved.enter,
    }

    local a = win(windows, { address = "0x1", class = "Dofus.x64" })
    local b = win(windows, { address = "0x2", class = "Dofus.x64" })
    open(stub, b)

    local order = {}
    for _, m in ipairs(a.group.members) do
      order[#order + 1] = m.address
    end
    t.eq({ "0x2", "0x1" }, order, "physical member order follows the adapter, not open/address order")

    group_adapters.registry["Dofus.x64"] = saved
  end)

  t.it("inserts a joining member at its adapter-ordered slot, not always at the end", function()
    local _, stub, windows = fresh_scene()
    local group_adapters = require("hypr.scene.group_adapters")
    local saved = group_adapters.registry["Dofus.x64"]
    -- Roster order: 0x1, 0x2, 0x3 — the joiner (0x2) belongs in the middle
    -- of the two windows already grouped (0x1, 0x3).
    local rank = { ["0x1"] = 1, ["0x2"] = 2, ["0x3"] = 3 }
    group_adapters.registry["Dofus.x64"] = {
      order = function(members)
        local addrs = {}
        for _, m in ipairs(members) do
          addrs[#addrs + 1] = m.address
        end
        table.sort(addrs, function(x, y)
          return rank[x] < rank[y]
        end)
        return addrs
      end,
      enter = saved.enter,
    }

    local a = win(windows, { address = "0x1", class = "Dofus.x64" })
    local d = win(windows, { address = "0x3", class = "Dofus.x64" })
    hl_stub.new_group({ a, d })
    local c = win(windows, { address = "0x2", class = "Dofus.x64" })

    open(stub, c)

    local order = {}
    for _, m in ipairs(a.group.members) do
      order[#order + 1] = m.address
    end
    t.eq({ "0x1", "0x2", "0x3" }, order, "the joiner lands between its roster neighbours, not appended")

    group_adapters.registry["Dofus.x64"] = saved
  end)

  t.it("does nothing for a lone block window with no peer yet", function()
    local calls, stub, windows = fresh_scene()
    local a = win(windows, { address = "0x1", class = "Dofus.x64" })
    open(stub, a)
    t.eq(nil, a.group)
    for _, record in ipairs(calls) do
      t.ok(record.event ~= "group_seed" and record.event ~= "group_join" and record.event ~= "group_eject")
    end
  end)
end)
