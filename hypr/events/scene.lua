-- Window scene engine (LEO-245): wiring.
--
-- A scene is a per-workspace arrangement of *blocks*. A block names the window
-- classes it owns and the invariants that hold between them: `group` (every
-- match lives in one Hyprland group, so the block is a single tile however
-- many windows it has), `order` (where its tile sits left-to-right), `share`
-- (how much of the tiled span it holds), `collect` (whether members that
-- wandered to another workspace are brought home — not executed today, see
-- docs/scenes.md#collect).
--
-- Geometry is decided by the registered layout provider alone
-- (`hl.layout.register`, `hypr/scene/provider.lua` + `layout.lua`): the
-- compositor calls `recalculate` on every change, so this file arms nothing
-- and corrects nothing. The corrective engine that used to sit between
-- events and the layout (`schedule.lua` + `model.lua` + `actuator.lua`) is
-- retired (LEO-261) — see "Hyprland primitives" in AGENTS.md.
--
-- The work that is left is split so each part can be read on its own:
--
--   hypr/scene/spec.lua      the declaration, normalized
--   hypr/scene/compile.lua   declaration -> static window rules, at config load
--   hypr/scene/companion.lua the declared spawn/companion lifecycle
--
-- This file connects those to Hyprland's events, plus decision-record logging
-- (LEO-352) and mode-scoped binding admission on workspace arrival.
local spec_lib = require("hypr.scene.spec")
local companion = require("hypr.scene.companion")
local hyprfocus = require("hypr.hyprfocus")
local trace = require("hypr.lib.trace")

local specs = spec_lib.load()

-- In-flight spawns, keyed workspace:companion-class, so a scan racing the
-- companion's own open event never asks twice. Cleared when the companion
-- maps or when the scan converges on another decision for the key; no timer
-- arms it, because the events are what a companion's presence rides anyway.
local pending = {}

---Decision-record fields common to every window-keyed log line: `trace` is
---the window address (docs/lifecycle.md Part B), so every stage for one
---window's lifetime is queryable by the same key.
---@param w HL.Window?
---@param scene_name string?
---@return table
local function window_fields(w, scene_name)
  return {
    trace = w and w.address,
    address = w and w.address,
    class = w and w.class,
    initial_class = w and w.initial_class,
    title = w and w.title,
    pid = w and w.pid,
    scene = scene_name,
    workspace = w and w.workspace and w.workspace.name,
  }
end

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
      trace.emit({
        stage = "interact",
        event = "companion_spawn",
        decision = "spawn",
        reason = decision.command,
        scene = name,
      })
      hl.dispatch(hl.dsp.exec_cmd(("uwsm app -- %s"):format(decision.command)))
    elseif decision.addresses then
      for _, address in ipairs(decision.addresses) do
        trace.emit({
          stage = "interact",
          event = "companion_close",
          decision = "close",
          reason = "companion reconverge",
          scene = name,
          trace = address,
          address = address,
        })
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

local M = {}

---Scene name owning this workspace, or nil.
---@param ws HL.Workspace?
---@return string?
function M.active(ws)
  local name = ws and ws.name
  return name and specs[name] and name or nil
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

-- Anything already open when the config (re)loads: companions get the same
-- treatment a live event would, so a desk that reloads between "member
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
  local scene_name = scene_for(w)
  -- identify/route as they exist today: a class either matches a scene's
  -- block (routed to it) or matches none (no scene claim, LEO-354 territory).
  local fields = window_fields(w, scene_name)
  fields.stage = "identify"
  fields.event = scene_name and "matched" or "unmatched"
  fields.decision = scene_name and "route" or "none"
  fields.reason = scene_name and ("matched scene " .. scene_name) or "no scene claims this class"
  trace.emit(fields)
  converge_companions(scene_name)
end)

hl.on("window.close", function(w)
  local name = w and scene_for(w)
  local fields = window_fields(w, name)
  fields.stage = "leave"
  fields.event = "closed"
  fields.decision = "leave"
  fields.reason = "window.close"
  trace.emit(fields)
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
end)

-- A cross-workspace move is a map into the destination in law: the window
-- becomes the destination scene's. Deliberately narrow — a move into one
-- scene must not re-converge companions for every other one unnecessarily.
hl.on("window.move_to_workspace", function(w)
  local scene_name = scene_for(w)
  local fields = window_fields(w, scene_name)
  fields.stage = "leave"
  fields.event = "moved"
  fields.decision = "move"
  fields.reason = "window.move_to_workspace"
  trace.emit(fields)
  -- A move flies two scenes: the destination gains a member and the origin
  -- may have lost its last, and the event's payload cannot say where from.
  -- The lifecycle re-derives from live windows like everything else here.
  converge_companions(scene_name)
  for other_scene, spec in pairs(specs) do
    for _, block in ipairs(spec.blocks) do
      if block.spawn then
        converge_companions(other_scene)
        break
      end
    end
  end
end)

-- Arriving on a workspace admits or withholds its scene's mode-scoped binding
-- trees (LEO-266). Arranging the workspace is not this file's job: the scene
-- layout provider is asked by the compositor on every change and needs no
-- event subscription (see "Hyprland primitives" in AGENTS.md).
hl.on("workspace.active", function()
  local ws = hl.get_active_workspace()
  local scene_name = M.active(ws)
  if scene_name then
    pcall(function()
      hyprfocus.apply_bindings(hyprfocus.active(), scene_name)
    end)
  end
end)

return M
