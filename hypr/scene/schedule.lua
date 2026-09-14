-- When the engine is allowed to act (LEO-245).
--
-- Three rules, and every storm the engine used to produce is one of them
-- being broken:
--
--   1. **Only the visible scene is corrected.** Reaching onto a hidden
--      workspace means focusing a window there, which takes the user with it
--      and fires `workspace.active`, which arms the next scene. A scene that
--      is behind the user is marked dirty and realized when they come back.
--   2. **Never act on a single reading.** Hyprland animates every correction,
--      so geometry sampled once is mid-flight. A pass acts only when two
--      reads a verify apart agree.
--   3. **Never repeat a correction that changed nothing.** If the geometry is
--      unchanged after applying an intent, applying it again is an
--      oscillation — the pass ends and the user's arrangement stands.
--
-- Everything is turn-bounded on top of that, so no chain of timers can run
-- away even if all three rules somehow hold at once.
local hyg = require("hypr.lib.hypr")
local model = require("hypr.scene.model")
local snapshot = require("hypr.scene.snapshot")
local actuator = require("hypr.scene.actuator")
local registry = require("hypr.scene.registry")

local M = {}

-- How long after an event until tiled geometry is final enough to aim at.
local SETTLE_MS = 100
-- Re-read this long after a correction, to see whether it landed.
local VERIFY_MS = 80
-- Corrections per pass. A join plus a reorder plus a resize is three; the
-- headroom is for a block whose windows arrive together.
local MAX_TURNS = 8

---@type table<string, Scene.Spec>
local specs = {}
---@type table<string, boolean> scene name -> a pass is running
local busy = {}
---@type table<string, boolean> scene name -> a pass is armed but not started
local pending = {}

---@param name string
local function run(name)
  local spec = specs[name]
  if not spec or busy[name] then
    return
  end
  busy[name] = true

  -- Pass-local, both of them. Carrying either across passes meant a pass that
  -- ran out of turns silently disarmed the next one's first correction.
  local turns, last_digest, last_key = 0, nil, nil

  local function finish()
    busy[name] = false
  end

  local function step()
    turns = turns + 1
    if turns > MAX_TURNS then
      -- Out of turns rather than out of work. Deliberately not re-armed here:
      -- a scene that burned a whole budget is losing an argument with
      -- something (a client that resizes itself, a layout that will not
      -- honor a width), and retrying immediately is that argument in a loop.
      -- The next event, or the next time the user walks back in, starts over
      -- with a fresh budget.
      return finish()
    end

    local snap = snapshot.read()
    if snap.active ~= name then
      -- The user left mid-pass. Nothing further is ours to touch; arriving
      -- back on the workspace is what starts the next pass.
      return finish()
    end

    local now = model.digest(spec, snap)
    if last_digest ~= now then
      last_digest = now
      return hyg.oneshot(VERIFY_MS, step)
    end

    local intent = model.intent(spec, snap, registry.owned(name))
    if not intent then
      return finish()
    end
    if intent.key == last_key then
      return finish()
    end
    last_key = intent.key
    actuator.apply(intent)
    -- Force a re-measure before the next decision: the correction is in
    -- flight, so this reading is stale by definition.
    last_digest = nil
    hyg.oneshot(VERIFY_MS, step)
  end

  step()
end

---Ask for a pass on `name`. Scheduling is a gate, not a queue: a burst of
---events collapses into one pass, and a scene already mid-pass keeps the
---verify chain it is running — corrections read live state at dispatch time,
---so a pass that starts a beat later fixes the same reality.
---@param name string?
function M.arm(name)
  if not name or not specs[name] or busy[name] or pending[name] then
    return
  end
  local active = hl.get_active_workspace()
  if not active or active.name ~= name then
    return
  end
  pending[name] = true
  hyg.oneshot(SETTLE_MS, function()
    pending[name] = nil
    run(name)
  end)
end

---The user arrived on a workspace: realize its scene if it is owed one, and
---on first arrival regardless (the arrangement they come back to should be
---the scene's, not whatever drifted while it was behind them).
---@param name string?
function M.on_enter(name)
  if name and specs[name] then
    M.arm(name)
  end
end

---@param loaded table<string, Scene.Spec>
function M.init(loaded)
  specs = loaded
  busy, pending = {}, {}
end

---Force a pass now, bypassing the settle gate but not the visibility rule.
---@param name string
function M.realize(name)
  run(name)
end

return M
