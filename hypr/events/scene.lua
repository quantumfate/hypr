-- Window scene engine (LEO-245): wiring.
--
-- A scene is a per-workspace arrangement of *blocks*. A block names the window
-- classes it owns and the invariants that hold between them: `group` (every
-- match lives in one Hyprland group, so the block is a single tile however
-- many windows it has), `order` (where its tile sits left-to-right), `share`
-- (how much of the tiled span it holds). A window a block claims is re-homed
-- to this workspace unconditionally, on open and on mode apply
-- (`hypr/scene/home.lua`, LEO-353) — not a per-block opt-in.
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
local identify = require("hypr.scene.identify")
local grouping = require("hypr.scene.grouping")
local group_adapters = require("hypr.scene.group_adapters")
local strays = require("hypr.scene.strays")
local home = require("hypr.scene.home")
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

---Keep `w` off an undeclared workspace (LEO-382): a window that opens or
---moves onto a plain workspace `workspace_specs` does not name is moved,
---address-targeted, to that monitor's declared workspace — a workspace no
---scene, shelf or binding addresses is otherwise stranded forever. Pure
---decision in `nav.off_undeclared`; a special or an ignored monitor's own
---plain workspace is left to `keep_off_ignored` above.
---@param w HL.Window?
local function keep_off_undeclared(w)
  local host = (rawget(_G, "config") or {}).host or {}
  local workspace_specs = (host.workspaces or {}).workspace_specs
  for _, action in ipairs(nav.off_undeclared(workspace_specs, host.ignored_monitors, host.primary_monitor, w)) do
    hl.dispatch(hl.dsp.window.move({
      window = "address:" .. action.move,
      workspace = "name:" .. action.workspace,
      follow = false,
    }))
    trace.emit({
      stage = "admit",
      event = "undeclared_workspace",
      decision = "move",
      reason = "workspace not in workspace_specs",
      window = action.move,
      workspace = action.workspace,
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
    stable_id = w and w.stable_id,
    tags = w and w.tags,
    scene = scene_name,
    workspace = w and w.workspace and w.workspace.name,
  }
  for key, value in pairs(extra or {}) do
    fields[key] = value
  end
  return fields
end

---Run one pipeline step in isolation. `window.open`/`window.move_to_workspace`
---chain several independent steps (identify, re-home, group, stray-float,
---undeclared/ignored placement) in one `hl.on` callback; Hyprland's own
---per-callback pcall (`LuaEventHandler.cpp`) only guards the callback as a
---whole and, on failure, pops a 5-second notification the compositor never
---writes to its log (`ConfigManager::addError` only logs while parsing/
---evaluating config, confirmed from source) -- so a throwing step used to both
---abort every later step for that window AND leave no queryable trace of why.
---Each step now runs isolated: a failure is caught, recorded as its own
---decision (queryable the same way every other stage is, via `trace`'s
---window-address key), and the steps after it for this window still run.
---@param step string
---@param w HL.Window?
---@param fn fun()
local function guarded(step, w, fn)
  local ok, err = pcall(fn)
  if not ok then
    trace.emit(window_fields(w, nil, {
      stage = "error",
      event = "handler_step_failed",
      decision = "skip",
      reason = tostring(err),
      step = step,
    }))
  end
end

---Run the companion lifecycle for the named scene against live windows.
---Presence is derived, so this is safe at any time from any caller.
---@param name string?
---@param exclude string? address of a window that just left. A window is
---still listed in `hl.get_windows()` while its own `window.close` event fires
---(spiked live), so the close path passes the payload's address to keep the
---member count honest for the scene it is leaving.
local function converge_companions(name, exclude)
  local spec = name and specs[name]
  if not spec then
    return
  end
  local windows = hl.get_windows() or {}
  if exclude then
    local kept = {}
    for _, w in ipairs(windows) do
      if w.address ~= exclude then
        kept[#kept + 1] = w
      end
    end
    windows = kept
  end
  for _, decision in ipairs(companion.filter(companion.decisions(spec, name, windows), pending)) do
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

---The pending registry carries a count per key: the engine's spawn arms one
---(companion.expire), a launch surface can arm several before they land
---(`M.arm_launch`). A window's open consumes at most one matching intent, and
---the key is dropped at zero so a consumed spawn is re-issued by the next
---convergence (presence is derived) instead of stalling on a stale marker.
---@param key string
local function claim_consume(key)
  local n = pending[key]
  if n == nil then
    return
  end
  n = type(n) == "number" and n or 1
  if n <= 1 then
    pending[key] = nil
  else
    pending[key] = n - 1
  end
end

---Claim the window an armed launch intent opened for (LEO-412): a pending
---key `workspace:class` is matched by class on ANY open, not only one on the
---intent scene's own workspace — with the profile shared, `+media-browser`
---pins the launched window to `name:media` before this pass sees it. The
---first intent a class match settles stamps the scene's free slot through
---`identify.assign_for` (scoped to the intent's workspace, so pokemon's two
---slots count siblings that were already claimed and sent home), which is
---what lets the block's slot claim and the home decision route the window to
---its scene. One open settles at most one intent; hand-opened windows with no
---intent armed are left untouched.
---@param w HL.Window?
local function claim_launched(w)
  if not (w and w.class) then
    return
  end
  local live = hl.get_windows() or {}
  local keys = {}
  for key in pairs(pending) do
    local class = key:match("^.-:(.+)$")
    if class and spec_lib.class_matches(w.class, { class }) then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local ws_name = key:match("^(.-):")
    local spec = ws_name and specs[ws_name]
    local tag = spec and identify.assign_for(spec, w, live, ws_name)
    claim_consume(key)
    if tag then
      hl.dispatch(hl.dsp.window.tag({ window = "address:" .. w.address, tag = "+" .. tag }))
      trace.emit(window_fields(w, ws_name, {
        stage = "identify",
        event = "launch_claimed",
        decision = "tag",
        reason = ("claimed %s for %s"):format(tag, ws_name),
      }))
      return
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
  return spec and spec_lib.block_for(spec, w.class, w.tags) and spec.name or nil
end

---Stamp the identity tag (LEO-364) `identify.assign` picks for `w`, if any:
---one of several same-class windows a scene's `slot` blocks need told apart
---(pokemon's two media browsers, `docs/scenes.md` "Ambiguous classes"). Runs
---before `scene_for` in the `window.open` handler so the rest of this pass
---sees the tag on `w` immediately — reading `w.tags` live, not through a
---rule the compositor would only evaluate at open (see identify.lua header).
---@param w HL.Window?
local function stamp_identity(w)
  local spec = w and w.workspace and specs[w.workspace.name]
  local tag = spec and identify.assign(spec, w, hl.get_windows() or {})
  if not tag then
    return
  end
  hl.dispatch(hl.dsp.window.tag({ window = "address:" .. w.address, tag = "+" .. tag }))
  trace.emit(window_fields(w, spec.name, {
    stage = "identify",
    event = "slot_assigned",
    decision = "tag",
    reason = "assigned " .. tag,
  }))
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
    -- Hyprland places members in the order they are `group:add`ed, not in
    -- whatever order the caller iterates them (the
    -- physical tab order didn't match the roster driving mod+j/k). Sort
    -- `decision.members` (address order, from grouping.lua) into the
    -- adapter's order first, so the first `add` call already lands the
    -- anchor the adapter would pick first.
    local by_address = {}
    for _, m in ipairs(decision.members) do
      by_address[m.address] = m
    end
    local ordered = {}
    for _, address in ipairs(group_adapters.for_class(w.class).order(decision.members, {})) do
      if by_address[address] then
        ordered[#ordered + 1] = by_address[address]
      end
    end

    local anchor = ordered[1] or decision.members[1]
    hl.dispatch(hl.dsp.group.toggle({ window = "address:" .. anchor.address }))
    local seeded = hl.get_window("address:" .. anchor.address)
    if seeded and seeded.group then
      local group_key = grouping.group_key(seeded)
      group_adapters.record_join(group_key, anchor.address)
      for i = 2, #ordered do
        local member = hl.get_window("address:" .. ordered[i].address)
        if member then
          pcall(function()
            seeded.group:add(member)
          end)
          group_adapters.record_join(group_key, ordered[i].address)
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
      -- Same reordering, for a window arriving after the group already
      -- exists: `HL.Group:add(window, index)` takes a 1-based insertion
      -- index (verified against Hyprland 0.56's Lua binding source), so the
      -- joiner is placed at its adapter-ordered slot among the group's
      -- current members instead of always landing at the end.
      local current = group_adapters.normalize_members(target.group)
      current[#current + 1] = { address = joiner.address, title = joiner.title }
      local group_key = grouping.group_key(target)
      local index
      for i, address in ipairs(group_adapters.for_class(w.class).order(current, { group_key = group_key })) do
        if address == joiner.address then
          index = i
          break
        end
      end
      pcall(function()
        target.group:add(joiner, index)
      end)
      group_adapters.record_join(group_key, w.address)
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

---Scene names admitted by the mode last applied, or an empty set before the
---first apply — a re-home never claims a window into a scene the mode is not
---currently running.
---@return table<string, true>
local function active_scenes()
  local desk = hyprfocus.applied_desk()
  local out = {}
  for _, placement in ipairs(desk and desk.scenes or {}) do
    out[placement.name] = true
  end
  return out
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
  local decision = strays.decide(spec, w, specs, active_scenes())
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

---Execute one `home.decide` decision (LEO-353): a claimed window is moved,
---address-targeted and unfollowed, to its scene's workspace. Runs before
---grouping/stray-float so a window about to leave never gets arranged into
---the workspace it is leaving; the destination's `window.move_to_workspace`
---handles arranging it once the move lands.
---@param w HL.Window?
---@return boolean moved
local function apply_home_decision(w)
  if not w then
    return false
  end
  local decision = home.decide(specs, active_scenes(), w)
  if decision.action ~= "move" then
    return false
  end
  local origin = w.workspace and w.workspace.name
  hl.dispatch(hl.dsp.window.move({
    window = "address:" .. w.address,
    workspace = "name:" .. decision.workspace,
    follow = false,
  }))
  if decision.settle then
    -- The window arrived floating (it was stray-floated on the wrong
    -- workspace before this claim fired). Its own scene never declared it
    -- floating, so clear it explicitly — `action = "off"`, not a toggle,
    -- since a toggle would float an already-tiled window instead (spiked
    -- live). Address-targeted: no focus-dance.
    hl.dispatch(hl.dsp.window.float({ window = "address:" .. w.address, action = "off" }))
  end
  trace.emit(window_fields(w, decision.workspace, {
    stage = "route",
    event = "collected",
    decision = "move",
    reason = ("claimed by %s, was on %s"):format(decision.workspace, origin or "?"),
  }))
  return true
end

local M = {}

---Scene name owning this workspace, or nil.
---@param ws HL.Workspace?
---@return string?
function M.active(ws)
  local name = ws and ws.name
  return name and specs[name] and name or nil
end

---Arm a launch intent: record that a window of `class` is about to be
---launched for the named scene, so its open is claimed on arrival like an
---engine spawn's (companion.expire arms the spawn's own key through this same
---registry). A launch surface (the pokemon media-open bind) calls this right
---before dispatching its exec — with the profile shared, the window maps
---wherever the profile's rules pin it, and the claim's `assign_for` stamps
---the scene's free slot so home routes it there instead. Counted: N rapid
---arms are N intents, each settled by its own matching open.
---@param name string scene name (the workspace `default_name` it owns)
---@param class string
function M.arm_launch(name, class)
  local key = companion.key(name, class)
  pending[key] = (type(pending[key]) == "number" and pending[key] or 0) + 1
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
    if ws and ws.name == name and not w.floating and w.at and spec_lib.block_for(spec, w.class, w.tags) == block then
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
  -- A class matching an armed launch intent is that launch settling: stamp
  -- its scene's free slot (LEO-412) before identity/home run, so the block's
  -- slot claim and the home decision route a pinned-then-claimed window home
  -- even though it mapped on another scene's workspace.
  guarded("claim_launched", w, function()
    claim_launched(w)
  end)
  -- Stamp identity before routing: `scene_for` and the arrange decisions
  -- below all read `w.tags`, so a slot block can only be matched if the tag
  -- lands first in this same pass.
  guarded("stamp_identity", w, function()
    stamp_identity(w)
  end)
  -- A window claimed by another active scene is on the wrong workspace by
  -- construction (it opened while nothing here claimed it): send it home
  -- before anything else acts on it standing where it is. The move lands as
  -- its own `window.move_to_workspace` event, which arranges the destination.
  -- `moved` stays false (rest of the pipeline still runs) if this step itself
  -- throws -- a home-decision failure must not also swallow every step below.
  local moved = false
  guarded("apply_home_decision", w, function()
    moved = apply_home_decision(w)
  end)
  if moved then
    return
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
  guarded("converge_companions", w, function()
    converge_companions(scene_name)
  end)
  guarded("apply_group_decision", w, function()
    apply_group_decision(w)
  end)
  guarded("apply_stray_decision", w, function()
    apply_stray_decision(w)
  end)
  guarded("keep_off_undeclared", w, function()
    keep_off_undeclared(w)
  end)
  guarded("keep_off_ignored", w, function()
    keep_off_ignored(w)
  end)
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
  -- re-derives for free — there is no remembered book to consult. The
  -- closing window is still in the live list during its own close event
  -- (spiked live), so it is excluded here: the scene it is leaving must see
  -- its member really gone, or the last member leaving never closes the
  -- block's companions.
  for scene_name, spec in pairs(specs) do
    for _, block in ipairs(spec.blocks) do
      if block.spawn then
        converge_companions(scene_name, w and w.address)
        break
      end
    end
  end
end)

-- A cross-workspace move is a map into the destination in law: the window
-- becomes the destination scene's. Deliberately narrow — a move into one
-- scene must not re-converge companions for every other one unnecessarily.
hl.on("window.move_to_workspace", function(w)
  -- A move into a slot scene is a map into it in law (see comment below):
  -- stamp identity here too, so a window moved in by hand still gets told
  -- apart from its same-class siblings.
  guarded("stamp_identity", w, function()
    stamp_identity(w)
  end)
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
  guarded("converge_companions", w, function()
    converge_companions(scene_name)
  end)
  guarded("apply_group_decision", w, function()
    apply_group_decision(w)
  end)
  guarded("apply_stray_decision", w, function()
    apply_stray_decision(w)
  end)
  guarded("converge_other_companions", w, function()
    for other_scene, spec in pairs(specs) do
      for _, block in ipairs(spec.blocks) do
        if block.spawn then
          converge_companions(other_scene)
          break
        end
      end
    end
  end)
  guarded("keep_off_undeclared", w, function()
    keep_off_undeclared(w)
  end)
  guarded("keep_off_ignored", w, function()
    keep_off_ignored(w)
  end)
end)

-- A group member gaining focus (tab cycle, `mod+j/k`, a click on the
-- groupbar) records it as the group's entry member (LEO-380 follow-up):
-- `hypr/lib/nav.lua`'s `mod+h/l` reads this back, through
-- `group_adapters`'s default `enter`, so entering a group next time lands
-- here again instead of always on its first member.
hl.on("window.active", function(w)
  if w and w.group then
    group_adapters.record_focus(grouping.group_key(w), w.address)
  end
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
