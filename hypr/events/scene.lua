-- Window scene engine (LEO-245): wiring.
--
-- A scene is a per-workspace arrangement of *blocks*. A block names the window
-- classes it owns and the invariants that hold between them: `group` (every
-- match lives in one Hyprland group, so the block is a single tile however
-- many windows it has), `order` (where its tile sits left-to-right), `share`
-- (how much of the tiled span it holds), `collect` (whether members that
-- wandered to another workspace are brought home).
--
-- The work is split so each part can be read on its own, and so the decisions
-- can be tested without a compositor:
--
--   hypr/scene/spec.lua      the declaration, normalized
--   hypr/scene/compile.lua   declaration -> static window rules, at config load
--   hypr/scene/snapshot.lua  the compositor's state, flattened to plain tables
--   hypr/scene/registry.lua  which windows a scene owns
--   hypr/scene/model.lua     snapshot + spec -> the one correction wanted (pure)
--   hypr/scene/actuator.lua  one correction -> compositor calls
--   hypr/scene/schedule.lua  when acting is allowed at all
--   hypr/scene/companion.lua the declared spawn/companion lifecycle
--
-- This file only connects them to Hyprland's events.
local spec_lib = require("hypr.scene.spec")
local registry = require("hypr.scene.registry")
local schedule = require("hypr.scene.schedule")
local companion = require("hypr.scene.companion")

local specs = spec_lib.load()

schedule.init(specs)
registry.seed(specs)

-- In-flight spawns, keyed workspace:companion-class, so a scan racing the
-- companion's own open event never asks twice. Cleared when the companion
-- maps or when the scan converges on another decision for the key; no timer
-- arms it, because the events are what a companion's presence rides anyway.
local pending = {}

---Run the companion lifecycle for the named scene against live windows.
---Presence is derived, so this is safe at any time from any caller.
---@param name string?
local function converge_companions(name)
  local spec = name and specs[name]
  if not spec then
    return
  end
  for _, decision in ipairs(companion.filter(companion.decisions(spec, name, hl.get_windows() or {}), pending)) do
    if decision.action == "spawn" then
      companion.expire(decision.pending_key, pending)
      hl.dispatch(hl.dsp.exec_cmd(("uwsm app -- %s"):format(decision.command)))
    elseif decision.addresses then
      for _, address in ipairs(decision.addresses) do
        hl.dispatch(hl.dsp.window.close({ window = "address:" .. address }))
      end
      pending[decision.pending_key] = nil
    end
  end
end

---The scene whose blocks `w` belongs to, or nil. Keyed by the workspace's
---`default_name`, never its id: ids are assigned by the compositor and are
---host data (this host runs gaming on 4 while the laptop writes 5), so
---matching against spec numbers is a race-wired guess.
---@param w HL.Window?
---@return string?
local function scene_for(w)
  -- Guarding `w` first, not `w and w.workspace and ...`: reading `w.class`
  -- below stays honest about what is guaranteed.
  if not w then
    return nil
  end
  local spec = w.workspace and specs[w.workspace.name]
  return spec and spec_lib.block_for(spec, w.class) and spec.name or nil
end

-- Anything already open when the config (re)loads: the handlers below replay
-- no history, so a reload would otherwise leave every live scene unowned.
for _, w in ipairs(hl.get_windows() or {}) do
  schedule.arm(scene_for(w))
end
-- Companions get the same treatment: a desk that reloads between "member
-- opened" and "companion opened" still owes the lifecycle — presence is
-- derived, so converging once here converges structs already on the desk.
for scene_name, spec in pairs(specs) do
  for _, block in ipairs(spec.blocks) do
    if block.spawn then
      converge_companions(scene_name)
      break
    end
  end
end

hl.on("window.open", function(w)
  registry.claim(specs, w)
  -- A companion mapping settles its own in-flight spawn before the engine
  -- pass runs, so the lifecycle the pass sees is derived, not assumed.
  if w and w.workspace then
    local spec = specs[w.workspace.name]
    if spec then
      for _, block in ipairs(spec.blocks) do
        if block.spawn and spec_lib.class_matches(w.class, { block.spawn.class }) then
          pending[companion.key(w.workspace.name, block.spawn.class)] = nil
        end
      end
    end
  end
  converge_companions(scene_for(w))
  schedule.arm(scene_for(w))
end)

hl.on("window.close", function(w)
  local name = w and scene_for(w)
  registry.forget(w and w.address)
  -- A close event's payload may not say where the window stood, but the
  -- lifecycle is derived from live windows, so every spawn-carrying scene
  -- re-derives for free — there is no remembered book to consult.
  for scene_name, spec in pairs(specs) do
    for _, block in ipairs(spec.blocks) do
      if block.spawn then
        converge_companions(scene_name)
        break
      end
    end
  end
  schedule.arm(name)
end)

-- A cross-workspace move is a map into the destination in law: the window
-- becomes the destination scene's, and the scene it left re-checks its
-- arrangement without it. Deliberately narrow — a move into one scene must
-- not re-arrange every other one.
hl.on("window.move_to_workspace", function(w)
  registry.claim(specs, w)
  -- A move flies two scenes: the destination gains a member and the origin
  -- may have lost its last, and the event's payload cannot say where from.
  -- The lifecycle re-derives from live windows like everything else here.
  converge_companions(scene_for(w))
  for scene_name, spec in pairs(specs) do
    for _, block in ipairs(spec.blocks) do
      if block.spawn then
        converge_companions(scene_name)
        break
      end
    end
  end
  schedule.arm(scene_for(w))
end)

-- Arriving on a workspace is the moment its scene may act: whatever drifted
-- while it was behind the user is corrected now, in front of them, where a
-- focus-dance cannot carry them anywhere they did not ask to go.
hl.on("workspace.active", function()
  local ws = hl.get_active_workspace()
  schedule.on_enter(ws and ws.name)
end)

local M = {}

---Scene name owning this workspace, or nil.
---@param ws HL.Workspace?
---@return string?
function M.active(ws)
  local name = ws and ws.name
  return name and specs[name] and name or nil
end

---Run the realize loop for the named scene.
---@param name string
function M.realize(name)
  if specs[name] then
    schedule.realize(name)
  end
end

---Leftmost live tile of the block matching `match`, or nil.
---@param name string
---@param match string|{ class: string }
---@return HL.Window?
function M.tile(name, match)
  local spec = specs[name]
  local class = type(match) == "table" and match.class or match
  local block = spec and type(class) == "string" and spec_lib.block_for(spec, class)
  if not block then
    return nil
  end
  local best
  for _, w in ipairs(hl.get_windows() or {}) do
    local ws = w.workspace
    if ws and ws.name == name and not w.floating and w.at and spec_lib.block_for(spec, w.class) == block then
      if not best or w.at.y < best.at.y or (w.at.y == best.at.y and w.at.x < best.at.x) then
        best = w
      end
    end
  end
  return best
end

return M
