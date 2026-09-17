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
local grouping = require("hypr.scene.grouping")
local group_adapters = require("hypr.scene.group_adapters")
local strays = require("hypr.scene.strays")
local hyprfocus = require("hypr.hyprfocus")
local trace = require("hypr.lib.trace")
local nav = require("hypr.lib.nav")

local specs = spec_lib.load()

-- In-flight spawns, keyed workspace:companion-class, so a scan racing the
-- companion's own open event never asks twice. Cleared when the companion
-- maps or when the scan converges on another decision for the key; no timer
-- arms it, because the events are what a companion's presence rides anyway.
local pending = {}

---Keep the desk off the host's ignored monitors (`config.host.ignored_monitors`):
---a special shown there is re-shown on the primary, and a window standing on
---one of its plain workspaces moves, address-targeted, to the primary's active
---workspace.
---@param w HL.Window?
local function keep_off_ignored(w)
  local host = (rawget(_G, "config") or {}).host or {}
  local actions = nav.off_ignored(host.ignored_monitors, host.primary_monitor, hl.get_monitors() or {}, w)
  for _, action in ipairs(actions) do
    if action.show then
      hl.dispatch(hl.dsp.focus({ monitor = host.primary_monitor }))
      hl.dispatch(hl.dsp.workspace.toggle_special(action.show))
    else
      hl.dispatch(hl.dsp.window.move({
        window = "address:" .. action.move,
        workspace = "name:" .. action.workspace,
        follow = false,
      }))
    end
    trace.emit({
      stage = "admit",
      event = "ignored_monitor",
      decision = action.show and "show_on_primary" or "move",
      reason = "ignored monitor",
      window = action.move,
      workspace = action.show or action.workspace,
      monitor = host.primary_monitor,
    })
  end
end

---Decision-record fields common to every window-keyed log line: `trace` is
---the window address (docs/lifecycle.md Part B), so every stage for one
---window's lifetime is queryable by the same key.
---@param w HL.Window?
---@param scene_name string?
---@param extra table? stage/event/decision/reason/block, merged over the base fields
---@return table
local function window_fields(w, scene_name, extra)
  local fields = {
    trace = w and w.address,
    address = w and w.address,
    class = w and w.class,
    initial_class = w and w.initial_class,
    title = w and w.title,
    pid = w and w.pid,
    scene = scene_name,
    workspace = w and w.workspace and w.workspace.name,
  }
  for key, value in pairs(extra or {}) do
    fields[key] = value
  end
  return fields
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

---Execute one `grouping.decide` decision (LEO-369): `hl.dispatch`/`HL.Group`
---calls the spike verified live, never a loop or timer. `seed` folds every
---currently ungrouped block peer in the same pass, since a peer that opened
---first has no future event of its own to catch it.
---The scene is read from `w`'s workspace directly, not `scene_for` (which
---only names a scene when the window's own class matches one of its
---blocks): an ejectable foreigner's class matches no block by definition,
---but its workspace still owns a scene whose group it was swallowed into.
---@param w HL.Window?
local function apply_group_decision(w)
  local spec = w and w.workspace and specs[w.workspace.name]
  if not spec then
    return
  end
  local scene_name = spec.name
  local decision = grouping.decide(spec, w, hl.get_windows() or {})
  local block_field = decision.block and ("%s/%d"):format(scene_name, decision.block.order)

  if decision.action == "seed" and decision.members and #decision.members >= 2 then
    local anchor = decision.members[1]
    hl.dispatch(hl.dsp.group.toggle({ window = "address:" .. anchor.address }))
    local seeded = hl.get_window("address:" .. anchor.address)
    if seeded and seeded.group then
      local group_key = grouping.group_key(seeded)
      group_adapters.record_join(group_key, anchor.address)
      for i = 2, #decision.members do
        local member = hl.get_window("address:" .. decision.members[i].address)
        if member then
          pcall(function()
            seeded.group:add(member)
          end)
          group_adapters.record_join(group_key, decision.members[i].address)
        end
      end
    end
    trace.emit(window_fields(w, scene_name, {
      stage = "arrange",
      event = "group_seed",
      decision = "seed",
      reason = "seeded block group",
      block = block_field,
    }))
  elseif decision.action == "join" and decision.target then
    local target = hl.get_window("address:" .. decision.target.address)
    local joiner = hl.get_window("address:" .. w.address)
    if target and target.group and joiner then
      pcall(function()
        target.group:add(joiner)
      end)
      group_adapters.record_join(grouping.group_key(target), w.address)
    end
    trace.emit(window_fields(w, scene_name, {
      stage = "arrange",
      event = "group_join",
      decision = "join",
      reason = "joined block group",
      block = block_field,
    }))
  elseif decision.action == "eject" then
    local victim = hl.get_window("address:" .. w.address)
    if victim and victim.group then
      local group_key = grouping.group_key(victim)
      pcall(function()
        victim.group:remove(victim)
      end)
      group_adapters.record_leave(group_key, w.address)
    end
    trace.emit(window_fields(w, scene_name, {
      stage = "arrange",
      event = "group_eject",
      decision = "eject",
      reason = "foreign window ejected from block group",
      block = block_field,
    }))
  end
end

---Execute one `strays.decide` decision (LEO-367): float the window
---address-targeted, no focus-dance. Tiled layout targets never include a
---floated window (`hypr/scene/provider.lua` reads `hl.get_windows()`'s own
---`floating` field), so once this dispatch lands the stray drops out of the
---scene layout's split on the next `recalculate` for free.
---@param w HL.Window?
local function apply_stray_decision(w)
  local spec = w and w.workspace and specs[w.workspace.name]
  if not spec then
    return
  end
  local decision = strays.decide(spec, w)
  if decision.action ~= "float" then
    return
  end
  hl.dispatch(hl.dsp.window.float({ window = "address:" .. w.address }))
  trace.emit(window_fields(w, spec.name, {
    stage = "arrange",
    event = "stray_float",
    decision = "float",
    reason = "unblocked window on a strays=float scene",
  }))
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
  apply_group_decision(w)
  apply_stray_decision(w)
  keep_off_ignored(w)
end)

hl.on("window.close", function(w)
  local name = w and scene_for(w)
  local fields = window_fields(w, name)
  fields.stage = "leave"
  fields.event = "closed"
  fields.decision = "leave"
  fields.reason = "window.close"
  trace.emit(fields)
  -- A closing group member leaves the default adapter's join-order record
  -- too, same as an ejection (LEO-380): the group either shrinks or, if
  -- `w` was the last member, `w.group` is already gone and there is
  -- nothing to forget.
  if w and w.group then
    group_adapters.record_leave(grouping.group_key(w), w.address)
  end
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
  apply_group_decision(w)
  apply_stray_decision(w)
  for other_scene, spec in pairs(specs) do
    for _, block in ipairs(spec.blocks) do
      if block.spawn then
        converge_companions(other_scene)
        break
      end
    end
  end
  keep_off_ignored(w)
end)

-- Arriving on a workspace admits or withholds its scene's mode-scoped binding
-- trees (LEO-266). Arranging the workspace is not this file's job: the scene
-- layout provider is asked by the compositor on every change and needs no
-- event subscription (see "Hyprland primitives" in AGENTS.md).
hl.on("workspace.active", function()
  keep_off_ignored(nil)
  -- A scene workspace created after the last apply (or after its output
  -- appeared) still stands where it was made; stand it on its role's output.
  pcall(hyprfocus.replace, true)
  local ws = hl.get_active_workspace()
  local scene_name = M.active(ws)
  if scene_name then
    pcall(function()
      hyprfocus.apply_bindings(hyprfocus.active(), scene_name)
    end)
  end
end)

return M
