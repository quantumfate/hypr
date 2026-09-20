-- The companion lifecycle executor (LEO-411): hypr/events/scene.lua's
-- window.open/window.close wiring around hypr/scene/companion.lua's
-- decisions. `tests/companion_spec.lua` covers the pure decisions; this
-- asserts the dispatches end to end against a stub shaped like the live
-- compositor — including the ordering quirk a closing window is still in
-- `hl.get_windows()` during its own `window.close` event (spiked live), the
-- cost of which is that the close path must exclude the payload's address or
-- the last member leaving never closes the block's companions.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")
local hl_stub = require("tests.hl_stub")

-- Dofus-shaped: a member block carrying the spawn, and a second tile block
-- naming the companion class — the shape that lets each spawned companion's
-- own open event re-converge the scene. Mirrors tests/e2e/fixtures.
local SPAWNER = {
  blocks = {
    {
      classes = { "e2e-member" },
      order = 1,
      spawn = { class = "e2e-companion", command = "foot --app-id e2e-companion sh -c sleep 600", max_spawns = 3 },
    },
    { classes = { "e2e-companion" }, order = 2 },
  },
  barred = {},
}

-- The same shape without a cap: one companion per member, the pre-LEO-411
-- contract, used to pin the below-cap refill on a closed companion.
local SINGLE = {
  blocks = {
    {
      classes = { "e2e-member" },
      order = 1,
      spawn = { class = "e2e-companion", command = "foot --app-id e2e-companion" },
    },
    { classes = { "e2e-companion" }, order = 2 },
  },
  barred = {},
}

---@param scenes table
---@return table calls, table stub, table[] windows
local function fresh_scene(scenes)
  local calls = {}
  package.loaded["hypr.lib.trace"] = {
    emit = function(record)
      calls[#calls + 1] = record
    end,
  }

  local stub = hl_stub.new()
  _G.hl = stub
  _G.config = { host = { workspaces = { workspace_specs = {} } } }

  package.loaded["hypr.lib.store"] = {
    define = function()
      return {
        get = function()
          return { base = { scenes = scenes } }
        end,
        put = function() end,
      }
    end,
  }

  package.loaded["hypr.hyprfocus"] = {
    applied_desk = function()
      return { scenes = { { name = "spawner" }, { name = "single" } } }
    end,
    apply_bindings = function() end,
    active = function() end,
    replace = function() end,
  }

  for _, mod in ipairs({
    "hypr.lib.hypr",
    "hypr.lib.nav",
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

  local windows = {}
  stub.get_windows = function()
    return windows
  end
  stub.get_active_workspace = function()
    return { id = 7, name = "spawner" }
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
    workspace = { id = 7, name = over.ws },
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
local function close(stub, w)
  for _, cb in ipairs(stub.event_handlers["window.close"] or {}) do
    cb(w)
  end
end

---@param stub table
---@return table[] commands dispatched through dsp.exec_cmd
local function spawn_commands(stub)
  local cmds = {}
  for _, action in ipairs(stub.dispatched) do
    if action.name == "dsp.exec_cmd" then
      cmds[#cmds + 1] = action.args[1]
    end
  end
  return cmds
end

---@param stub table
---@return table[] window selectors dispatched through dsp.window.close
local function close_dispatches(stub)
  local out = {}
  for _, action in ipairs(stub.dispatched) do
    if action.name == "dsp.window.close" then
      out[#out + 1] = action.args[1] and action.args[1].window
    end
  end
  return out
end

t.describe("companion executor", function()
  t.it("fills the cap one spawn per convergence, never overshooting", function()
    local _, stub, windows = fresh_scene({ spawner = SPAWNER })
    local member = win(windows, { address = "0xa1", class = "e2e-member", ws = "spawner" })
    open(stub, member)
    t.eq(1, #spawn_commands(stub), "the first member maps one companion spawn")

    for i = 1, 3 do
      -- Companion spawns land by event: each window's own open fires as it
      -- appears, before any later one exists — the timing the cap's one-at-a-
      -- time fill rides.
      win(windows, { address = "0xb" .. i, class = "e2e-companion", ws = "spawner" })
      open(stub, windows[#windows])
    end
    t.eq(3, #spawn_commands(stub), "one spawn per companion's own open, to the cap")

    win(windows, { address = "0xbc", class = "e2e-companion", ws = "spawner" })
    open(stub, windows[#windows])
    t.eq(3, #spawn_commands(stub), "a fourth companion at the cap spawns nothing")
  end)

  t.it("a burst while a spawn is in flight admits one; the mapping heals the marker and the fill resumes", function()
    local _, stub, windows = fresh_scene({ spawner = SPAWNER })
    local member = win(windows, { address = "0xa1", class = "e2e-member", ws = "spawner" })
    open(stub, member)
    -- A second member opens before any companion mapped: the in-flight marker
    -- is a duplicate guard, not a presence record, so the burst is admitted
    -- one spawn at a time — below the cap but still no second dispatch.
    local burst = win(windows, { address = "0xa2", class = "e2e-member", ws = "spawner" })
    open(stub, burst)
    t.eq(1, #spawn_commands(stub), "the in-flight marker admits one spawn inside the event gap")

    -- The first spawned companion lands: its own open settles the marker and
    -- re-converges the next, so the fill resumes one per convergence.
    local c1 = win(windows, { address = "0xb1", class = "e2e-companion", ws = "spawner" })
    open(stub, c1)
    t.eq(2, #spawn_commands(stub), "a mapping self-heals the marker and the next spawn fires")
  end)

  t.it("the last member leaving closes every companion while the closing window still lists", function()
    local calls, stub, windows = fresh_scene({ spawner = SPAWNER })
    local member = win(windows, { address = "0xa1", class = "e2e-member", ws = "spawner" })
    open(stub, member)
    for i = 1, 3 do
      win(windows, { address = "0xb" .. i, class = "e2e-companion", ws = "spawner" })
    end
    open(stub, windows[2])
    open(stub, windows[3])
    open(stub, windows[4])

    -- The close payload's window is still in the live list — the exact
    -- compositor ordering the bug rode in on. Only excluding it here counts
    -- the member really gone.
    close(stub, member)

    local closed = close_dispatches(stub)
    table.sort(closed)
    t.eq(
      "address:0xb1,address:0xb2,address:0xb3",
      table.concat(closed, ","),
      "all companions close with the last member"
    )

    local records = {}
    for _, record in ipairs(calls) do
      if record.event == "companion_close" then
        records[#records + 1] = record.address
      end
    end
    t.eq(3, #records, "each close is recorded as its own decision")
  end)

  t.it("a closed companion stops counting below the cap, so the scene refills at once", function()
    local _, stub, windows = fresh_scene({ single = SINGLE })
    local member = win(windows, { address = "0xa1", class = "e2e-member", ws = "single" })
    open(stub, member)
    local companion = win(windows, { address = "0xb1", class = "e2e-companion", ws = "single" })
    open(stub, companion)
    t.eq(1, #spawn_commands(stub), "one companion mapped, cap of one satisfied")

    -- The user closes the companion; it is still listed (live ordering), but
    -- excluding it drops the count below the cap, so the scene asks again.
    close(stub, companion)
    t.eq(2, #spawn_commands(stub), "the scene refills while a member still stands")
    t.eq(0, #close_dispatches(stub), "closing a companion never closes the member")
  end)
end)
