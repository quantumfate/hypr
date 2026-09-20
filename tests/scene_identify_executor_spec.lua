-- The identity executor (LEO-364): hypr/events/scene.lua's window.open/
-- window.move_to_workspace wiring around hypr/scene/identify.lua. These
-- assert end to end — the real `hl.dispatch` call and the `identify.matched`
-- routing it unlocks — not just the pure decision `scene_identify_spec.lua`
-- already covers.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field
local t = require("tests.harness")
local hl_stub = require("tests.hl_stub")

local POKEMON = {
  blocks = {
    { classes = { "com.libretro.RetroArch" }, order = 1 },
    { classes = { "zen-twilight-media" }, order = 2, slot = "pokemon/chat" },
    { classes = { "zen-twilight-media" }, order = 3, slot = "pokemon/stream" },
  },
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

  local scenes = { pokemon = POKEMON }
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

  for _, mod in ipairs({ "hypr.lib.hypr", "hypr.scene.spec", "hypr.scene.identify", "hypr.events.scene" }) do
    package.loaded[mod] = nil
  end

  local windows = {}
  stub.get_windows = function()
    return windows
  end
  stub.get_active_workspace = function()
    return { id = 5, name = "pokemon" }
  end

  -- Simulates the spiked-live compositor (LEO-364/LEO-369): a tag dispatch
  -- lands on the window synchronously, so the rest of this event pass reads
  -- it straight off `w.tags` like a real Hyprland handle would.
  function stub.dispatch(action)
    stub.dispatched[#stub.dispatched + 1] = action
    if type(action) == "table" and action.name == "dsp.window.tag" then
      local arg = action.args[1] or {}
      local address = arg.window and arg.window:match("^address:(.+)$")
      local w = address and stub.get_window("address:" .. address)
      local added = arg.tag and arg.tag:match("^%+(.+)$")
      if w and added then
        w.tags = w.tags or {}
        w.tags[#w.tags + 1] = added
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
  local w = { address = over.address, class = over.class, tags = over.tags, workspace = { id = 5, name = "pokemon" } }
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

t.describe("identity executor", function()
  t.it("stamps the first free slot tag on the first same-class window", function()
    local calls, stub, windows = fresh_scene()
    local a = win(windows, { address = "0x1", class = "zen-twilight-media" })
    open(stub, a)

    t.eq({ "slot:pokemon/chat" }, a.tags, "window ends up carrying the slot tag")

    local assigned = {}
    for _, record in ipairs(calls) do
      if record.event == "slot_assigned" then
        assigned[#assigned + 1] = record
      end
    end
    t.eq(1, #assigned, "exactly one slot_assigned record")
    t.eq("identify", assigned[1].stage)
    t.eq("0x1", assigned[1].address)
  end)

  t.it("stamps the next free slot on a second live sibling, and both route to their own block", function()
    local calls, stub, windows = fresh_scene()
    local a = win(windows, { address = "0x1", class = "zen-twilight-media" })
    open(stub, a)
    local b = win(windows, { address = "0x2", class = "zen-twilight-media" })
    open(stub, b)

    t.eq({ "slot:pokemon/chat" }, a.tags)
    t.eq({ "slot:pokemon/stream" }, b.tags)

    -- Both are routed (`identify.matched`) in the same pass the tag landed
    -- in — proof the tag is read live, not through a rule evaluated later
    -- (AGENTS.md "Hyprland primitives", spiked live).
    local matched = 0
    for _, record in ipairs(calls) do
      if record.event == "matched" and record.address == b.address then
        matched = matched + 1
      end
    end
    t.eq(1, matched, "the second window is routed once it carries its own slot tag")
  end)

  t.it("does not restamp a window that already carries its slot", function()
    local calls, stub, windows = fresh_scene()
    local a = win(windows, { address = "0x1", class = "zen-twilight-media", tags = { "slot:pokemon/chat" } })
    open(stub, a)

    t.eq({ "slot:pokemon/chat" }, a.tags, "no second tag appended")
    for _, record in ipairs(calls) do
      t.ok(record.event ~= "slot_assigned", "no slot_assigned record for an already-tagged window")
    end
  end)
end)
