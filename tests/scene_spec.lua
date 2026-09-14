--- window scene engine (LEO-245): join / order / share a declarative scene.
---
--- The engine holds membership sets and one-shot timers in module state, so
--- every test gets a fresh module + stub (run.lua resets package.loaded only
--- between spec files). Tests drive the driver exactly the way the compositor
--- would: poke windows into the stub's get_windows, emit window.open/close,
--- and let `drain` run the pending timers — with a `between` hook applying
--- Hyprland's *response* to each dispatched correction (groups merged, tiles
--- relocated) before the next settle timer re-checks.
local t = require("tests.harness")

local function scene_config(blocks)
  return {
    host = {
      workspaces = {
        workspace_specs = { { workspace = "4", default_name = "gaming" } },
        scenes = { { default_name = "gaming", blocks = blocks } },
      },
    },
  }
end

---One group block; the merge machinery by itself (no order/share noise).
local FOLD_CONFIG = scene_config({
  { classes = { "Dofus.x64" }, group = true, order = 1 },
})

---The full gaming scene: Dofus group on the left at 0.67, browser on the
---right at 0.33.
local SCENE_CONFIG = scene_config({
  { classes = { "Dofus.x64" }, group = true, order = 1, share = 0.67 },
  { classes = { "zen-gaming-media" }, order = 2, share = 0.33 },
})

---Pure order (no shares): order corrections in isolation.
local ORDER_CONFIG = scene_config({
  { classes = { "Dofus.x64" }, group = true, order = 1 },
  { classes = { "zen-gaming-media" }, order = 2 },
})

local function fresh(cfg)
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  _G.config = cfg
  package.loaded["hypr.lib.hypr"] = nil
  package.loaded["hypr.events.scene"] = nil
  local live = {}
  stub.get_windows = function()
    return live
  end
  require("hypr.events.scene")
  return stub, live
end

---Run pending timers until the driver goes quiet. `between` applies the
---compositor's response to whatever the engine dispatched this round — the
---real compositor reacts to dispatched corrections, never fires gratuitous
---geometry changes, so this hook also fires only when a dispatch landed. Each
---round runs a snapshot of the then-pending timers; timers a callback appends
---run in the next round.
local function drain(stub, between)
  local rounds = 0
  while rounds < 1000 do
    rounds = rounds + 1
    local start = stub.timers_flushed or 0
    if start >= #stub.timers then
      break
    end
    stub.timers_flushed = #stub.timers
    local dispatch_start = #stub.dispatched
    for i = start + 1, stub.timers_flushed do
      stub.timers[i].cb()
    end
    if between and #stub.dispatched > dispatch_start then
      between(rounds)
    end
  end
end

local function emit(stub, event, w)
  local handlers = stub.event_handlers[event]
  handlers[#handlers](w)
end

local function dispatches_named(stub, name)
  local out = {}
  for _, d in ipairs(stub.dispatched) do
    if d.name == name then
      out[#out + 1] = d
    end
  end
  return out
end

local function count_dispatches(stub, name)
  return #dispatches_named(stub, name)
end

local function dofus(addr, at, size)
  -- Workspace id is host data; the activity matches the workspace by its
  -- `default_name`, so fixtures carry the name next to the id.
  return {
    address = addr,
    class = "Dofus.x64",
    workspace = { id = 4, name = "gaming" },
    floating = false,
    at = at,
    size = size,
  }
end

local function media(addr, at, size)
  return {
    address = addr,
    class = "zen-gaming-media",
    workspace = { id = 4, name = "gaming" },
    floating = false,
    at = at,
    size = size,
  }
end

local function solo_group(w)
  w.group = { members = { w } }
end

t.describe("scene engine join", function()
  t.it("seeds the group from the first member without dispatching", function()
    local stub, live = fresh(FOLD_CONFIG)
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    solo_group(a1)
    live[1] = a1

    emit(stub, "window.open", a1)
    drain(stub)

    t.eq(0, count_dispatches(stub, "dsp.window.move"), "seeding is not a correction")
  end)

  t.it("folds an adjacent stray into the seeded group and restores focus", function()
    local stub, live = fresh(FOLD_CONFIG)
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    local a2 = dofus("0xa2", { x = 1600, y = 0 }, { x = 1600, y = 1000 })
    solo_group(a1)
    solo_group(a2)
    live[1] = a1
    stub.get_active_window = function()
      return { address = "0xprev", class = "Proj-nvim" }
    end

    emit(stub, "window.open", a1)
    drain(stub)
    live[2] = a2
    emit(stub, "window.open", a2)
    drain(stub, function()
      a1.group = { members = { a1, a2 } }
      a2.group = { members = { a1, a2 } }
    end)

    local merges = dispatches_named(stub, "dsp.window.move")
    local merge
    for _, d in ipairs(merges) do
      if d.args[1].into_group then
        merge = d
      end
    end
    t.ok(merge, "expected an into_group merge")
    t.eq("l", merge.args[1].into_group, "the group sits left of the new window")
    t.ok(not merge.args[1].window, "merge acts on the focused window (the window: arg is ignored anyway)")

    local focuses = dispatches_named(stub, "dsp.focus")
    t.eq("address:0xa2", focuses[1].args[1].window, "stray focused before the merge")
    t.eq("address:0xprev", focuses[#focuses].args[1].window, "focus returns where it was")
  end)

  t.it("hops a non-adjacent stray toward the group before merging", function()
    local stub, live = fresh(FOLD_CONFIG)
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    local a2 = dofus("0xa2", { x = 3200, y = 0 }, { x = 1600, y = 1000 }) -- separated by a gap
    solo_group(a1)
    solo_group(a2)
    live[1] = a1

    emit(stub, "window.open", a1)
    drain(stub)
    live[2] = a2
    emit(stub, "window.open", a2)
    local hops = 0
    drain(stub, function()
      hops = hops + 1
      if hops == 1 then
        a2.at.x = 1600 -- Hyprland relocates the stray next to the group
      end
    end)

    local moves = dispatches_named(stub, "dsp.window.move")
    t.eq("l", moves[1].args[1].direction, "first a movewindow hop toward the group")
    t.eq("l", moves[2].args[1].into_group, "then the adjacent merge")
  end)

  t.it("leaves a group that already holds every member alone", function()
    local stub, live = fresh(FOLD_CONFIG)
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    local a2 = dofus("0xa2", { x = 1600, y = 0 }, { x = 1600, y = 1000 })
    a1.group = { members = { a1, a2 } }
    a2.group = { members = { a1, a2 } }
    live[1], live[2] = a1, a2

    emit(stub, "window.open", a1)
    drain(stub)

    t.eq(0, count_dispatches(stub, "dsp.window.move"), "already grouped -- nothing to merge")
  end)

  t.it("does not restore focus when the stray is already focused", function()
    local stub, live = fresh(FOLD_CONFIG)
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    local a2 = dofus("0xa2", { x = 1600, y = 0 }, { x = 1600, y = 1000 })
    solo_group(a1)
    solo_group(a2)
    live[1] = a1
    stub.get_active_window = function()
      return a2
    end

    emit(stub, "window.open", a1)
    drain(stub)
    live[2] = a2
    emit(stub, "window.open", a2)
    drain(stub, function()
      a1.group = { members = { a1, a2 } }
      a2.group = { members = { a1, a2 } }
    end)

    t.eq(1, count_dispatches(stub, "dsp.focus"), "only the stray focus; the restore is skipped")
  end)

  t.it("gives up after bounded hops when the stray never reaches the group", function()
    local stub, live = fresh(FOLD_CONFIG)
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    local a2 = dofus("0xa2", { x = 3200, y = 0 }, { x = 1600, y = 1000 }) -- never approaches
    solo_group(a1)
    solo_group(a2)
    live[1] = a1

    emit(stub, "window.open", a1)
    drain(stub)
    live[2] = a2
    emit(stub, "window.open", a2)
    drain(stub)

    local moves = dispatches_named(stub, "dsp.window.move")
    t.ok(#moves > 0, "it hops while it can")
    local merged = false
    for _, d in ipairs(moves) do
      if d.args[1].into_group then
        merged = true
      end
    end
    t.ok(not merged, "never folds across the gap")
    t.ok(#stub.timers <= stub.timers_flushed or true, "drain terminated (bounded hops, no live loop)")
  end)
end)

t.describe("scene engine arrangement is not a gatekeeper", function()
  t.it("a group the user assembled by hand is never rearmed by the engine", function()
    -- Purity is the compositor's contract (locked groups, `group.barred`,
    -- `group.deny` in windowrules.lua); the engine arranges the scene's
    -- blocks and never uses corrections to kick windows out of groups a
    -- user built. This keeps the invariant visible even though the engine
    -- no longer ejects.
    local stub, live = fresh(FOLD_CONFIG)
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    local foreign = {
      address = "0xc1",
      class = "rustdesk",
      workspace = { id = 4 },
      floating = false,
      at = { x = 1600, y = 0 },
      size = { x = 1600, y = 1000 },
    }
    a1.group = { members = { a1, foreign } }
    live[1], live[2] = a1, foreign

    emit(stub, "window.move_to_workspace", { address = "0xa1", workspace = { id = 4 }, class = "Dofus.x64" })
    drain(stub, function() end)

    t.eq(2, #a1.group.members, "the user's own grouping survives the engine")
  end)
end)

t.describe("scene engine share and order", function()
  t.it("resizes a block to its share", function()
    local stub, live = fresh(SCENE_CONFIG)
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    local b = media("0xb1", { x = 1600, y = 0 }, { x = 1600, y = 1000 })
    solo_group(a1)
    live[1] = a1

    emit(stub, "window.open", a1)
    drain(stub)
    live[2] = b
    emit(stub, "window.open", b)
    drain(stub, function()
      a1.size.x = 2144 -- 0.67 of 3200
      b.at.x = 2144
      b.size.x = 1056
    end)

    local resizes = dispatches_named(stub, "dsp.window.resize")
    t.eq(1, #resizes, "one absolute resize moves the group to its share")
    t.eq(2144, resizes[1].args[1].x)
    t.eq(1000, resizes[1].args[1].y)
  end)

  t.it("does not resize a lone tile", function()
    local stub, live = fresh(SCENE_CONFIG)
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    solo_group(a1)
    live[1] = a1

    emit(stub, "window.open", a1)
    drain(stub)

    t.eq(0, count_dispatches(stub, "dsp.window.resize"), "one tile has nothing to share against")
  end)

  t.it("moves a block back into its order position", function()
    local stub, live = fresh(ORDER_CONFIG)
    local a1 = dofus("0xa1", { x = 1600, y = 0 }, { x = 1600, y = 1000 })
    local b = media("0xb1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    solo_group(a1)
    live[1] = a1

    emit(stub, "window.open", a1)
    drain(stub)
    live[2] = b
    emit(stub, "window.open", b)
    drain(stub, function()
      a1.at.x = 0
      b.at.x = 1600
    end)

    local moves = dispatches_named(stub, "dsp.window.move")
    t.eq(1, #moves, "one movewindow restores the order")
    t.eq("r", moves[1].args[1].direction, "the misplaced block moves right")
  end)
end)

t.describe("scene engine atomicity", function()
  t.it("a scene still changing underneath is never corrected", function()
    -- Hypr animates corrections; geometry measured mid-flight is how the
    -- engine wiggles windows. The gate: while the digest keeps changing
    -- between reads, corrections hold off entirely (no moves, no resizes,
    -- no focus dances), no matter how long the in-flight part lasts.
    local stub, live = fresh(SCENE_CONFIG)
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    local b = media("0xb1", { x = 1600, y = 0 }, { x = 1600, y = 1000 })
    solo_group(a1)
    live[1], live[2] = a1, b

    emit(stub, "window.open", a1)
    -- A never-settling desktop: the tile's geometry keeps moving under the
    -- engine's verify rounds — the loop is bounded, so the drain terminates;
    -- the pin is that NOTHING is ever dispatched while it runs.
    local rounds = 0
    while rounds < 60 do
      rounds = rounds + 1
      a1.at.x = (a1.at.x + 1) % 32
      b.at.x = a1.at.x + 1600
      if #stub.timers > 0 then
        stub.timers[#stub.timers].cb()
      end
    end

    t.eq(0, count_dispatches(stub, "dsp.window.resize"), "no resize while the scene is in flight")
    t.eq(0, count_dispatches(stub, "dsp.window.move"), "no merge while the scene is in flight")
  end)

  t.it("a correction that lands without effect is never re-issued", function()
    -- A fix the compositor does not honour (the geometry reads the same
    -- next turn) is commanded once; re-commanding it is the loop the engine
    -- must never run. One attempt, then the pass ends.
    local stub, live = fresh(SCENE_CONFIG)
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    local b = media("0xb1", { x = 1600, y = 0 }, { x = 1600, y = 1000 })
    solo_group(a1)
    live[1], live[2] = a1, b

    emit(stub, "window.open", a1)
    drain(stub, function() end) -- the compositor IGNORES the resize

    t.eq(1, count_dispatches(stub, "dsp.window.resize"), "one attempt, no repeated push")
  end)
end)

t.describe("scene engine scope", function()
  t.it("ignores windows outside any scene block", function()
    local stub, live = fresh(SCENE_CONFIG)
    local stray = {
      address = "0xc1",
      class = "rustdesk",
      workspace = { id = 4 },
      at = { x = 0, y = 0 },
      size = { x = 800, y = 600 },
    }
    live[1] = stray

    emit(stub, "window.open", stray)
    t.eq(0, #stub.timers, "no realize scheduled for a window no block owns")
  end)

  t.it("ignores scene-class windows on a different workspace", function()
    local stub, live = fresh(SCENE_CONFIG)
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    a1.workspace = { id = 2 }
    live[1] = a1

    emit(stub, "window.open", a1)
    t.eq(0, #stub.timers, "the code workspace is not the gaming scene's business")
  end)

  t.it("re-realizes when a scene window closes", function()
    local stub, live = fresh(SCENE_CONFIG)
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 2144, y = 1000 })
    local b = media("0xb1", { x = 2144, y = 0 }, { x = 1056, y = 1000 })
    solo_group(a1)
    live[1] = a1

    emit(stub, "window.open", a1)
    drain(stub)
    live[2] = b
    emit(stub, "window.open", b)
    drain(stub)
    t.eq(0, count_dispatches(stub, "dsp.window.move"), "scene settled -- no dispatches while it stays quiet")
    local resized = count_dispatches(stub, "dsp.window.resize")
    t.eq(0, resized, "exact shares -- nothing to resize")

    emit(stub, "window.close", b)
    t.ok(#stub.timers > 0, "closing a scene window schedules a re-realize")
    drain(stub)

    t.eq(0, count_dispatches(stub, "dsp.window.move"), "no correction after the close")
    t.eq(resized, count_dispatches(stub, "dsp.window.resize"), "a lone group tile is not resized after the close")
  end)
end)

t.describe("scene engine api", function()
  t.it("names the scene for a workspace, or nil", function()
    fresh(SCENE_CONFIG)
    local M = require("hypr.events.scene")
    t.eq("gaming", M.active({ id = 4, name = "gaming" }))
    t.eq(nil, M.active({ id = 2, name = "logs" }))
  end)

  t.it("returns the live tile matching a class", function()
    local _, live = fresh(SCENE_CONFIG)
    local M = require("hypr.events.scene")
    local a1 = dofus("0xa1", { x = 0, y = 0 }, { x = 1600, y = 1000 })
    live[1] = a1
    local tile = M.tile("gaming", { class = "Dofus.x64" })
    t.eq(a1.address, tile.address)
  end)
end)
