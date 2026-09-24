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
local dock_publish = require("hypr.scene.dock_publish")
local deck = require("hypr.scene.deck")

local specs = spec_lib.load()

-- Standing down (`M.quiet`). Maintenance on the applications a scene keeps
-- alive -- wiping a browser profile, say -- means closing windows the scene
-- exists to reopen, and the reconverge wins that race every time. The flag
-- lives in the store rather than this state, so it survives the config
-- reload such work usually involves, and it carries a DEADLINE rather than a
-- boolean: a pause nobody lifts is a desk that has quietly stopped being a
-- desk, so it expires on its own.
local quiet_store = require("hypr.lib.store").define("scene-quiet")

---The deadline while one stands, or nil. Expiry is read, never written: a
---stale deadline is simply in the past.
---@return number?
local function quiet_until()
  local ok, value = pcall(function()
    return quiet_store:get("until")
  end)
  if not ok or type(value) ~= "number" then
    return nil
  end
  return value > os.time() and value or nil
end

-- In-flight spawns, keyed workspace:companion-class, so a scan racing the
-- companion's own open event never asks twice. Cleared when the companion
-- maps or when the scan converges on another decision for the key; no timer
-- arms it, because the events are what a companion's presence rides anyway.
local pending = {}

-- Focus source to restore to after a spawned or launched companion maps. A
-- chain of cap fills can spawn several companions in sequence; the source is
-- the member that triggered the first spawn, inherited while the chain lasts.
local spawn_source = {}

-- How long to wait after a claimed companion maps before returning focus, so
-- the new window has landed but the user has not had time to react.
local FOCUS_RETURN_MS = 50

---Whether a remembered spawn source is still alive on the workspace it was
---recorded for.
---@param entry table?
---@return table?
local function valid_source(entry)
  if not entry then
    return nil
  end
  local w = hl.get_window("address:" .. entry.address)
  if not w or not w.workspace or w.workspace.name ~= entry.workspace then
    return nil
  end
  return entry
end

-- Scene names the running mode admits. Forward-declared because companion
-- convergence below is gated on it, and the definition (which reads the
-- applied desk, with the pointer as the pre-apply fallback) lives further down.
local active_scenes

---Keep the desk off the host's ignored monitors (`config.host.ignored_monitors`):
---a special shown there is re-shown on the primary, and a window standing on
---one of its plain workspaces moves, address-targeted, to the primary's active
---workspace.
---
---Relocating a special necessarily flashes focus through the primary (a
---special shows on the focused monitor), which used to be left there: the user
---was on DP-2, a shelf on the ignored panel pulled them to DP-1. The focus is
---therefore put back on the monitor they were already on once the relocation
---has landed, so the ignored panel is corrected without taking the desk with
---it (LEO-423). A window move carries no such flash and is never followed by a
---focus dispatch.
---@param w HL.Window?
local function keep_off_ignored(w)
  local host = (rawget(_G, "config") or {}).host or {}
  local actions = nav.off_ignored(host.ignored_monitors, host.primary_monitor, hl.get_monitors() or {}, w)
  local before = (hl.get_active_monitor() or {}).name
  local relocated = false
  for _, action in ipairs(actions) do
    if action.show then
      relocated = true
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
  local restore = relocated and nav.restore_after_relocate(host.ignored_monitors, before, host.primary_monitor) or nil
  if restore then
    -- After the relocation has had a tick to land, not in the same breath as
    -- it: the toggle targets the primary, and an immediate refocus would race
    -- it. Bounded and one-shot, so it can never become a focus loop.
    require("hypr.lib.hypr").oneshot(50, function()
      hl.dispatch(hl.dsp.focus({ monitor = restore }))
    end)
    trace.emit({
      stage = "admit",
      event = "ignored_monitor_refocus",
      decision = "restore",
      reason = "relocating a special on an ignored monitor must not keep focus",
      monitor = restore,
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
  -- Only a scene the running mode admits has companions. This used to run for
  -- every spawn-carrying scene on every event and at load, so a withdrawn
  -- scene's companion opened onto whatever workspace was focused — the code
  -- scene's `zen-twilight` landing on dofus as a floating stray (LEO-423).
  if not active_scenes()[name] then
    return
  end
  -- Never judge presence while a mode apply is mid-shuffle. The apply holds,
  -- restores and withdraws members in phases, and an event landing between
  -- those phases sees the wrong admitted set — which is what closed the code
  -- scene's browser while its members were merely being parked on the
  -- holding place (a companion whose members come back must come back with
  -- them). The apply reconverges every admitted scene itself once its phases
  -- are done (M.reconverge).
  if hyprfocus.applying() then
    return
  end
  if quiet_until() then
    -- Standing down: something outside the desk is working on these windows
    -- (wiping a browser profile is the case this exists for), and the scene
    -- would undo it by reopening every companion the moment it closed.
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
      local active = hl.get_active_window()
      local source, source_ws
      if active and active.workspace and active.workspace.name == name then
        local block = spec_lib.block_for(spec, active.class, active.tags)
        if block and block.spawns and #block.spawns > 0 then
          source = active.address
          source_ws = name
          spawn_source[name] = { address = source, workspace = source_ws }
        end
      end
      if not source then
        local inherited = valid_source(spawn_source[name])
        if inherited and inherited.workspace == name then
          source = inherited.address
          source_ws = inherited.workspace
        end
      end
      companion.expire(decision.pending_key, pending)
      local entry = pending[decision.pending_key]
      if entry and source then
        entry.source = source
        entry.workspace = source_ws
      end
      trace.emit({
        stage = "interact",
        event = "companion_spawn",
        decision = "spawn",
        reason = decision.command,
        scene = name,
      })
      hl.dispatch(hl.dsp.exec_cmd(("uwsm app -- %s"):format(decision.command)))
    elseif decision.action == "adopt" then
      -- The window is alive and parked; this scene takes it rather than
      -- asking for one more. Stamping the slot first keeps the claim honest:
      -- the move lands on the workspace the tag already says it belongs to.
      local address = decision.address
      local live = hl.get_windows() or {}
      local w
      for _, candidate in ipairs(live) do
        if candidate.address == address then
          w = candidate
        end
      end
      if w then
        local tag = identify.assign_for(spec, w, live, name)
        if tag then
          hl.dispatch(hl.dsp.window.tag({ window = "address:" .. address, tag = "+" .. tag }))
        end
        require("hypr.hyprfocus.hold").release(address)
        hl.dispatch(hl.dsp.window.move({
          window = "address:" .. address,
          workspace = "name:" .. name,
          follow = false,
        }))
        trace.emit({
          stage = "interact",
          event = "companion_adopted",
          decision = "move",
          reason = "a parked window of this class answers the spawn",
          scene = name,
          trace = address,
          address = address,
        })
      end
      pending[decision.pending_key] = nil
    elseif decision.addresses then
      -- Only addresses the compositor still knows. A companion that closed
      -- on its own between the scan and this dispatch is already gone, and
      -- asking the compositor to close it again is an error it reports on
      -- screen — a handful of them at once on a mode swap, which is when the
      -- most companions reconverge.
      local live = {}
      for _, w in ipairs(hl.get_windows() or {}) do
        if w.address then
          live[w.address] = true
        end
      end
      for _, address in ipairs(decision.addresses) do
        if live[address] then
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
  local entry = pending[key]
  if type(entry) ~= "table" then
    pending[key] = nil
    return
  end
  if entry.count <= 1 then
    pending[key] = nil
  else
    entry.count = entry.count - 1
  end
end

---After a launched or spawned window maps, return focus to the window that
---was focused when the intent was armed, unless the user or another event has
---already moved focus elsewhere.
---@param w HL.Window the window that consumed the intent
---@param intent Scene.PendingIntent the pending intent entry that was consumed
local function restore_focus_after_claim(w, intent)
  local source_addr = intent.source
  if not source_addr then
    return
  end
  -- Do not fight a mode transition: transition.lua suspends focus-on-activate
  -- and raises a no_focus guard for the bracket, so opens already map unfocused.
  local transition = require("hypr.lib.transition")
  if transition.active() then
    return
  end
  require("hypr.lib.hypr").oneshot(FOCUS_RETURN_MS, function()
    if transition.active() then
      return
    end
    local source = hl.get_window("address:" .. source_addr)
    if not source then
      return
    end
    if intent.workspace and source.workspace and source.workspace.name ~= intent.workspace then
      return
    end
    local current = hl.get_active_window()
    if current and current.address == source_addr then
      return
    end
    -- If focus is no longer on the newly mapped window, something else (a
    -- user click or a later event) has taken it; don't fight that.
    if current and current.address ~= w.address then
      return
    end
    hl.dispatch(hl.dsp.focus({ window = "address:" .. source_addr }))
    trace.emit({
      stage = "interact",
      event = "focus_restored",
      decision = "refocus",
      reason = "spawned/launched window stole focus; returned to source",
      window = source_addr,
      trace = source_addr,
    })
  end)
end

---Claim the window an armed launch intent opened for (LEO-412): a pending
---key `workspace:class` is matched by class on ANY open, not only one on the
---intent scene's own workspace — with the profile shared, `+media-browser`
---pins the launched window to `name:media` before this pass sees it. The
---first intent a class match settles stamps the scene's free slot through
---`identify.assign_for` (scoped to the intent's workspace, so a scene with
---several slots — dofus and media sharing the profile — counts siblings that
---were already claimed and sent home), which is what lets the block's slot
---claim and the home decision route the window to its scene. One open settles
---at most one intent; hand-opened windows with no intent armed are left
---untouched.
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
    local intent = pending[key]
    claim_consume(key)
    restore_focus_after_claim(w, intent)
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
---(dofus and media sharing the one browser profile, `docs/scenes.md`
---"Ambiguous classes"). Runs before `scene_for` in the `window.open` handler
---so the rest of this pass sees the tag on `w` immediately — reading `w.tags`
---live, not through a rule the compositor would only evaluate at open (see
---identify.lua header).
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

-- Bring a window the deck parked back to its scene's workspace. A group's
-- members must share a workspace, so a `group:add` of a held window silently
-- leaves it on the hold special and out of the group it just joined.
---@param member HL.Window?
---@param scene_name string
local function unhold(member, scene_name)
  local hold = require("hypr.scene.deck_provider").HOLD
  if member and member.workspace and member.workspace.name == hold then
    hl.dispatch(hl.dsp.window.move({
      window = "address:" .. member.address,
      workspace = "name:" .. scene_name,
      follow = false,
    }))
  end
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
  -- A window the deck has parked stands on a hold workspace, which owns no
  -- scene -- so reading the spec from the workspace alone gave a held window
  -- no grouping decision at all, and a block whose members were all parked
  -- could never converge. `hypr/scene/compile.lua` stamps each window with
  -- its scene (`scene:<name>`), so the parked ones still say where they
  -- belong.
  if not spec and w then
    for _, tag in ipairs(w.tags or {}) do
      local scene = tag:match("^scene:([^*]+)")
      if scene and specs[scene] then
        spec = specs[scene]
        break
      end
    end
  end
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
    unhold(anchor, scene_name)
    hl.dispatch(hl.dsp.group.toggle({ window = "address:" .. anchor.address }))
    local seeded = hl.get_window("address:" .. anchor.address)
    if seeded and seeded.group then
      local group_key = grouping.group_key(seeded)
      group_adapters.record_join(group_key, anchor.address)
      for i = 2, #ordered do
        local member = hl.get_window("address:" .. ordered[i].address)
        if member then
          unhold(member, scene_name)
          member = hl.get_window("address:" .. ordered[i].address) or member
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
      unhold(target, scene_name)
      unhold(joiner, scene_name)
      target = hl.get_window("address:" .. decision.target.address) or target
      joiner = hl.get_window("address:" .. w.address) or joiner
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

---Scene names admitted by the mode last applied. Before the first apply
---(config load, a reload) the applied desk is nil, so the pointer's effective
---mode is resolved instead — otherwise a reload would converge no companions
---at all, and the load-time pass exists to catch already-open members.
---@return table<string, true>
active_scenes = function()
  local desk = hyprfocus.applied_desk()
  if not desk then
    local declaration = hyprfocus.declaration()
    if declaration then
      local ok, resolved = pcall(require("hypr.hyprfocus.resolve").resolve, declaration, hyprfocus.active())
      if ok then
        desk = resolved
      end
    end
  end
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
  -- Fit the floating stray to its monitor once the float has landed: a floated
  -- tile keeps its tiled box, which is the whole screen on a wide monitor and
  -- can sit off it. Address-targeted, no focus change, no noise.
  local address = w.address
  require("hypr.lib.hypr").oneshot(50, function()
    local win = hl.get_window("address:" .. address)
    if not win or not win.floating then
      return
    end
    local monitor = win.monitor or (win.workspace and win.workspace.monitor)
    if not monitor then
      return
    end
    local width, height = strays.fit_size(monitor)
    hl.dispatch(hl.dsp.window.resize({ window = "address:" .. address, x = width, y = height }))
    hl.dispatch(hl.dsp.window.center({ window = "address:" .. address }))
  end)
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
---Stand the scene engine down for `seconds` (default 300, capped at an hour),
---or lift it with `false`. While quiet, companion convergence decides
---nothing: windows a scene keeps alive can be closed, replaced or wiped
---without being reopened under the hand doing the work.
---@param seconds number|false
---@return number? deadline
function M.quiet(seconds)
  if seconds == false then
    quiet_store:set({ ["until"] = 0 })
    trace.emit({
      stage = "interact",
      event = "scene_quiet",
      decision = "resume",
      reason = "the scene engine is converging again",
    })
    return nil
  end
  local span = math.min(math.max(tonumber(seconds) or 300, 1), 3600)
  local deadline = os.time() + span
  quiet_store:set({ ["until"] = deadline })
  trace.emit({
    stage = "interact",
    event = "scene_quiet",
    decision = "pause",
    reason = ("standing down for %ds"):format(span),
  })
  return deadline
end

---Whether the engine is standing down right now, and until when.
---@return number?
function M.quiet_until()
  return quiet_until()
end

function M.arm_launch(name, class)
  local key = companion.key(name, class)
  local active = hl.get_active_window()
  local source, source_ws
  -- A user-initiated launch records whatever window was focused on the scene
  -- workspace as the source; unlike engine spawns, the active member may be in
  -- a block that does not itself carry a spawn declaration.
  if active and active.workspace and active.workspace.name == name then
    source = active.address
    source_ws = name
    spawn_source[name] = { address = source, workspace = source_ws }
  end
  local existing = pending[key]
  if type(existing) ~= "table" then
    pending[key] = { count = 1, source = source, workspace = source_ws }
  else
    existing.count = existing.count + 1
    if source then
      existing.source = source
      existing.workspace = source_ws
    end
  end
end

---Whether a scene lets its windows maximise or go fullscreen. The desk's
---presentation rule: windows on ordinary scenes never sit maximized — an
---app asserting that state (zen re-requests maximize after its surface is
---remapped by a hold round trip, which read as "zen maximizes after a
---scene swap") is reconciled away. The scenes where fullscreen IS the
---design — the gaming mode's set (Dofus's capture region, the Steam scenes'
---`fullscreen_state` window rules, the media scene) — are allowed, read
---from the declaration's `modes.gaming` scene list so the gate stays
---declaration-driven: a mode added to gaming extends the allowance without
---code changes. A missing or unreadable declaration leaves the engine
---silent rather than fighting every window on the desk.
---@param scene_name string?
---@return boolean
function M.fullscreen_allowed(scene_name)
  if not scene_name then
    return false
  end
  local ok, declaration = pcall(hyprfocus.declaration)
  if not ok or type(declaration) ~= "table" or type(declaration.modes) ~= "table" then
    return true
  end
  local gaming = declaration.modes.gaming
  if type(gaming) ~= "table" or type(gaming.scenes) ~= "table" then
    return true
  end
  for _, placement in ipairs(gaming.scenes) do
    if placement.name == scene_name then
      return true
    end
  end
  return false
end

---A window's fullscreen/maximize state cleared, address-targeted, no focus
---dance. `w.fullscreen` is 1 (compositor fullscreen) or 2 (maximized); the
---toggle with the matching mode is what lands the state back at 0. This is
---only called from the `window.active` handler, so the toggle's implicit
---target — the focused window — is the window being cleared, and the
---dispatcher needs no window argument (the fork's shape, as the binds use
---it).
---@param w HL.Window?
local function clear_fullscreen(w)
  if not w or (w.fullscreen or 0) == 0 then
    return
  end
  hl.dispatch(hl.dsp.window.fullscreen({
    mode = w.fullscreen == 2 and "maximized" or "fullscreen",
  }))
  trace.emit({
    stage = "arrange",
    event = "fullscreen_cleared",
    decision = "clear",
    reason = "a non-gaming scene's window does not maximise",
    trace = w.address,
    fullscreen = w.fullscreen,
  })
end

---Converge every admitted scene's companions in one pass. The mode apply
---calls this once its phases are done: the per-event convergence is
---suspended while the apply runs (see `converge_companions`), so this is
---what respawns the companions of a scene the apply just restored —
---deterministically at the end of the shuffle, not whenever an event
---happens to land next.
function M.reconverge()
  for name in pairs(active_scenes()) do
    converge_companions(name)
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
    if block.spawns then
      converge_companions(scene_name)
      break
    end
  end
end

hl.on("window.open", function(w)
  -- A window arriving fullscreen on a scene whose design does not allow it
  -- is cleared before it is ever laid out: the same "windows on ordinary
  -- scenes do not maximise" contract the focus reconciliation enforces.
  guarded("clear_arrival_fullscreen", w, function()
    -- Only when the arrival is the focused window (the toggle's implicit
    -- target): the active handler covers every focus moment, so an
    -- arriving-but-unfocused window is left for its own focus.
    local active = hl.get_active_window()
    if
      (w.fullscreen or 0) ~= 0
      and active
      and active.address == w.address
      and not M.fullscreen_allowed(M.active(w.workspace))
    then
      clear_fullscreen(w)
    end
  end)
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

-- Keep the keyboard in the column a closing window is leaving.
--
-- Hyprland's own fallback picks whatever is next in its focus history, which
-- on a deck scene is routinely the OTHER column: closing a project tab landed
-- focus on the browser instead of on the rest of the project. That is the
-- same "focus stays in the column" rule `scroll_deck_column` already applies
-- when the strip moves. A close event still lists the closing window, so it
-- is excluded by address rather than by absence.
---@param w HL.Window? the window being closed
---@param scene_name string?
local function keep_focus_in_column(w, scene_name)
  local spec = scene_name and specs[scene_name]
  if not w or not w.address or not spec or not deck.applies(spec) then
    return
  end
  local leaving = deck.column_for(spec, { class = w.class, tags = w.tags })
  if not leaving then
    return
  end
  -- A group member first: the rest of the project is what the user was
  -- working in, and it is already on screen.
  local members = w.group and w.group.members
  members = (members and members.title) and { members } or (members or {})
  for _, member in ipairs(members) do
    if member.address and member.address ~= w.address then
      hl.dispatch(hl.dsp.focus({ window = "address:" .. member.address }))
      return
    end
  end
  -- Otherwise anything else standing in the same column on this workspace.
  local ws_name = w.workspace and w.workspace.name
  for _, other in ipairs(hl.get_windows() or {}) do
    if
      other.address ~= w.address
      and other.workspace
      and other.workspace.name == ws_name
      and deck.column_for(spec, { class = other.class, tags = other.tags }) == leaving
    then
      hl.dispatch(hl.dsp.focus({ window = "address:" .. other.address }))
      return
    end
  end
end

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
  keep_focus_in_column(w, name)
  -- A remembered spawn source that has closed can no longer be returned to.
  if w and w.address then
    for ws_name, entry in pairs(spawn_source) do
      if entry.address == w.address then
        spawn_source[ws_name] = nil
      end
    end
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
      if block.spawns then
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
  -- A remembered spawn source that left its workspace can no longer be
  -- returned to; clear it before the move re-evaluates the scene.
  if w and w.address and w.workspace then
    for ws_name, entry in pairs(spawn_source) do
      if entry.address == w.address and w.workspace.name ~= entry.workspace then
        spawn_source[ws_name] = nil
      end
    end
  end
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
        if block.spawns then
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
-- Windows the user floated deliberately (the `SUPER+ALT+T` toggle registers
-- the address here); a member in this set is never re-tiled by the float
-- reconciliation below, so a deliberate float stays until the user toggles
-- it off. Session-only, keyed by address.
local deliberate_floats = {}

---Register/unregister a window as deliberately floated. The float toggle
---bind calls this right after its dispatch; the window's own floating state
---on the next event pass says which way the toggle went.
---@param address string?
function M.arm_float(address)
  if address then
    deliberate_floats[address] = true
  end
end

---Clear the deliberate-float mark: the user toggled the window back.
---@param address string?
function M.disarm_float(address)
  if address then
    deliberate_floats[address] = nil
  end
end

---Whether a window's class is a claimed block member of its workspace's
---scene — the windows whose geometry the scene owns, and therefore the ones
---a drag-float strands out of the layout (a dragged member never re-tiles on
---its own: the layout has no float branch, and no float event exists to hook,
---spiked live on this build).
---@param w table?
---@return boolean
local function is_scene_member(w)
  if not w or not w.workspace or not w.workspace.name then
    return false
  end
  local scene = M.active(w.workspace)
  if not scene then
    return false
  end
  local spec = specs[scene]
  return spec ~= nil and spec_lib.block_for(spec, w.class, w.tags) ~= nil
end

hl.on("window.active", function(w)
  if w and w.group then
    group_adapters.record_focus(grouping.group_key(w), w.address)
  end
  -- The fullscreen reconciliation: a window that arrived maximized or
  -- fullscreen on a scene whose design does not allow it — zen re-requests
  -- maximize after its surface is remapped by a hold round trip, which read
  -- as "zen maximizes after a scene swap" — is cleared here and on every
  -- focus, so an app that re-asserts loses every round. Deliberate toggles
  -- (the maximize/fullscreen keybinds, via `M.arm_float`'s registry) are
  -- never fought, nor are the gaming mode's scenes, where fullscreen is the
  -- design.
  if w and (w.fullscreen or 0) ~= 0 and w.workspace and w.workspace.name then
    local scene_name = M.active(w.workspace)
    if scene_name and not M.fullscreen_allowed(scene_name) and not deliberate_floats[w.address] then
      clear_fullscreen(w)
    end
  end
  -- The float reconciliation: a block member of the focused scene that is
  -- floating on its own workspace is a drag artifact — the drag made the
  -- compositor float it, and nothing else would ever put it back (the
  -- layout sees no target, the strays executor only floats, nothing
  -- re-tiles). Re-tile it address-targeted, no focus dance. Deliberate
  -- floats (the keybind toggle) are marked and left alone until toggled
  -- off; so are non-members, which is `strays` and pip territory.
  if
    w
    and w.floating
    and w.workspace
    and w.workspace.name
    and not deliberate_floats[w.address]
    and is_scene_member(w)
  then
    hl.dispatch(hl.dsp.window.float({ window = "address:" .. w.address }))
    trace.emit({
      stage = "arrange",
      event = "member_refloat",
      decision = "tile",
      reason = "a dragged block member re-tiles on focus",
      scene = M.active(w.workspace.name),
      trace = w.address,
    })
  end
end)

-- Arriving on a workspace admits or withholds its scene's mode-scoped binding
-- trees (LEO-266). Arranging the workspace is not this file's job: the scene
-- layout provider is asked by the compositor on every change and needs no
-- event subscription (see "Hyprland primitives" in AGENTS.md).
---Retire dock maps for monitors whose workspace no longer declares any.
---
---The publish itself rides the layout pass, which a monitor showing an
---undeclared workspace (or an empty one) never runs -- so without this its
---last map stands, and quickshell keeps placing isles against boxes that
---belong to a scene now standing somewhere else entirely.
local function sweep_docks()
  local keep = {}
  for _, monitor in ipairs(hl.get_monitors() or {}) do
    local ws = monitor.active_workspace
    local spec = ws and ws.name and specs[ws.name]
    if monitor.name and spec and spec.docks then
      keep[monitor.name] = true
    end
  end
  dock_publish.sweep(keep)
end

hl.on("monitor.focused", function()
  pcall(sweep_docks)
end)

hl.on("workspace.active", function()
  pcall(sweep_docks)
  keep_off_ignored(nil)
  -- A scene workspace created after the last apply (or after its output
  -- appeared) still stands where it was made; stand it on its role's output.
  pcall(hyprfocus.replace, true)
  local ws = hl.get_active_workspace()
  local scene_name = M.active(ws)
  if scene_name then
    -- The bar owes this monitor the new scene's dock map NOW, synchronously:
    -- the arrival recalc below is a focus dispatch, and an app re-activating
    -- in the same breath (linear is the live case) bounces focus before it
    -- lands — leaving the previous scene's dock docs under this scene, which
    -- is the "bars wonky until a relog" report. The screen-frame isles are
    -- correct immediately; block-docked isles rest until the recalc refines.
    pcall(function()
      require("hypr.scene.provider").publish_arrival(scene_name)
    end)
    pcall(function()
      hyprfocus.apply_bindings(hyprfocus.active(), scene_name)
    end)
  end
end)

return M
