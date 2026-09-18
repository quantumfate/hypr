-- The compositor's half of hyprfocus: read the declaration, apply what a mode
-- admits of it.
--
-- This is the seam between the pure modules and the running desk. Everything
-- it calls is decided elsewhere — `resolve` says what a mode means, `plan`
-- says what would change — so the only judgement here is which registries to
-- hand the answer to, and in what order.
--
-- Nothing wires itself to a reload: config load is application-time, not
-- desk-time. `apply` is called by `enter` (keyboard entry) and by the watcher
-- (`hypr/hyprfocus/watch.lua`, armed at start), which converges on whatever
-- the pointer names; a reload then converges on the pointer's mode within a
-- tick rather than as a side effect of loading config.
local store = require("hypr.lib.store")
local resolve = require("hypr.hyprfocus.resolve")
local plan = require("hypr.hyprfocus.plan")
local boot = require("hypr.hyprfocus.boot")
local binds = require("hypr.hyprfocus.binds")
local workspaces = require("hypr.hyprfocus.workspaces")
local hold = require("hypr.hyprfocus.hold")
local whichkey = require("hypr.lib.whichkey")
local trace = require("hypr.lib.trace")
local scene_spec = require("hypr.scene.spec")
local home = require("hypr.scene.home")
local nav = require("hypr.lib.nav")

local M = {}

--- The mode this runtime last applied successfully, and nil before the first
--- apply. Readers of "what is running" (the watcher) compare against this
--- rather than against what the pointer says, which can drift deliberately
--- (the shell edits it without the compositor running).
local applied = nil

--- The scene whose bindings were last admitted, so a change in scene can
--- re-admit without re-running the whole mode transition.
local applied_scene = nil

-- The declaration store, seeded from the shell repo on first run and editable
-- at runtime. mtime-cached by the store handle, so reading it per mode change
-- costs nothing when it has not changed.
local DECLARATION = "hyprfocus"
-- The active-mode pointer. Separate from the declaration on purpose: one
-- changes by the minute, the other by configuration.
local POINTER = "focus"

-- The half of a transition this runtime does not own. Named rather than
-- resolved to a path: it is on PATH precisely so it works from a terminal with
-- no compositor, and hardcoding a location here would undo that.
local CLI = ",hyprfocus"

--- The desk this runtime last applied, so a returning monitor can re-place
--- its scenes without resolving again.
---@type Hyprfocus.Desk?
local applied_desk = nil

--- True while `apply` runs. Its dispatched moves raise the very events the
--- watcher converges on, and an apply nested inside another one read the
--- held-window record before the outer one wrote it; the outer write then
--- dropped the inner entries, leaving windows in the holding place with no
--- origin and no way back. A nested call now refuses instead.
local applying = false

---@return table? declaration, string? error
function M.declaration()
  local ok, handle = pcall(store.define, DECLARATION)
  if not ok then
    return nil, tostring(handle)
  end
  local data = handle:get()
  if type(data) ~= "table" or not data.modes then
    return nil, "no declaration in the store"
  end
  return data, nil
end

--- Whether an ISO-8601 UTC (`Z`) stamp is in the past. Malformed input reads
--- as not-yet-expired, the same tolerant rule `hypr/lib/focus_gate.lua` uses.
---
--- `os.time(t)` treats `t`'s fields as LOCAL time, but `until_at`'s fields are
--- UTC — feeding them straight in silently shifts the comparison by the
--- host's UTC offset (wrong by 2h on a CEST machine, say). `local_utc_gap`
--- is that offset, computed once by round-tripping "now" through both
--- calendars, then added back to correct the parsed stamp.
---
--- `os.date("!*t", now)` stamps its table with `isdst = false` (UTC has no
--- DST), and `os.time` on a table with `isdst` set trusts it instead of
--- consulting the host's DST rules for that date — so during DST the gap
--- came out an hour short (CEST measured as CET) and a still-running timed
--- mode read as expired an hour early. Clearing `isdst` before the
--- round-trip lets `os.time` resolve DST for the date itself, the same way
--- it already does for the `stamp` table below (which never sets it).
---@param until_at string?
---@return boolean
local function expired(until_at)
  if type(until_at) ~= "string" then
    return false
  end
  local y, mo, d, h, mi = until_at:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
  if not y then
    return false
  end
  local now = os.time()
  local utc_now = os.date("!*t", now)
  utc_now.isdst = nil
  local local_utc_gap = now - os.time(utc_now)
  local stamp = os.time({
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
  }) + local_utc_gap
  return stamp < now
end

---The mode actually in effect: the pointer's `mode`, unless a timed mode has
---expired, in which case `previous` (the mode it was layered over) applies,
---falling back to `work`, the desk's resting mode. `neutral` is never a
---fallback here — it is a hidden recovery mode, reached only deliberately.
---@param pointer table? the pointer document, as read from the store
---@return string
local function effective_mode(pointer)
  pointer = pointer or {}
  local mode = pointer.mode or "work"
  if expired(pointer["until"]) then
    return pointer.previous or "work"
  end
  return mode
end
M.effective_mode = effective_mode
-- Exposed for `M.boot` (executor) and its spec (pure decision), both of
-- which need the same expiry test rather than a second implementation of it.
M.expired = expired

---@return string the mode the pointer names, or the resting state
function M.active()
  local ok, handle = pcall(store.define, POINTER)
  if not ok then
    return "work"
  end
  return effective_mode(handle:get())
end

---Resolve a mode, emitting a structured refusal when its scene set is
---invalid. The whole mode is refused: nothing is applied and the caller
---returns the reason.
---@param declaration table
---@param mode string
---@param emit boolean? emit the refusal record (once per transition)
---@return Hyprfocus.Desk?, string? error
local function desk_for(declaration, mode, emit)
  local refused = resolve.validate(declaration, mode)
  if refused and refused.refusal ~= "unknown_mode" then
    if emit then
      trace.emit(refused)
    end
    return nil, refused.reason
  end
  local ok, desk = pcall(resolve.resolve, declaration, mode)
  if not ok then
    return nil, tostring(desk)
  end
  return desk, nil
end

---The output a host monitor role names, and whether it had to fall back.
---A role whose output is not connected lands on primary (reason
---`monitor_missing`); `monitor.added` re-places it once it returns.
---@param role string
---@return string? output, string? fallback reason
local function output_for(role)
  local host = (rawget(_G, "config") or {}).host or {}
  local wanted = host[role .. "_monitor"]
  local connected = {}
  for _, monitor in ipairs(nav.usable_monitors(hl.get_monitors() or {}, host.ignored_monitors)) do
    connected[monitor.name] = true
  end
  if wanted and connected[wanted] then
    return wanted, nil
  end
  return host.primary_monitor, "monitor_missing"
end

-- Exposed for the workspace-row binds (`hypr/binds.lua`), which resolve "the
-- Nth scene on the focused monitor" at press time from the same desk and
-- role->output mapping a mode transition already used to place it.
M.output_for = output_for

---The output a workspace currently stands on, or nil when it does not exist.
---@param name string
---@return string?
local function current_output(name)
  local ok, workspace = pcall(hl.get_workspace, "name:" .. name)
  if ok and workspace and workspace.monitor then
    return workspace.monitor.name
  end
  return nil
end

---Put each active scene's workspace on the output its monitor role resolves
---to. The mode's role wins over the host file's workspace pin, which is only
---the load-time default.
---@param desk Hyprfocus.Desk
---@param quiet boolean? log only the moves (the per-focus re-place)
---@return { scene: string, role: string, output: string?, moved: boolean, reason: string? }[]
function M.place(desk, quiet)
  local placed = {}
  for _, placement in ipairs(desk.scenes or {}) do
    local output, fallback = output_for(placement.monitor)
    local current = current_output(placement.name)
    local moved = output ~= nil and current ~= nil and current ~= output
    if moved then
      hl.dispatch(hl.dsp.workspace.move({ workspace = "name:" .. placement.name, monitor = output }))
    end
    if moved or not quiet then
      trace.emit({
        stage = "admit",
        event = "scene_monitor",
        decision = moved and "move" or "keep",
        reason = fallback or ("mode " .. desk.mode .. " places it on " .. placement.monitor),
        mode = desk.mode,
        scene = placement.name,
        workspace = placement.name,
        monitor = output,
      })
    end
    placed[#placed + 1] = {
      scene = placement.name,
      role = placement.monitor,
      output = output,
      moved = moved,
      reason = fallback,
    }
  end
  return placed
end

---Re-place the last applied desk's scenes, for a monitor that came back or a
---scene workspace created where its role does not put it.
---@param quiet boolean? log only the moves
---@return table[] placements, empty before the first apply
function M.replace(quiet)
  if not applied_desk then
    return {}
  end
  return M.place(applied_desk, quiet)
end

---What the desk currently holds, in the shape the planner compares against.
---@return Hyprfocus.Running
function M.running()
  local live_workspaces = {}
  for _, name in ipairs(workspaces.names()) do
    live_workspaces[#live_workspaces + 1] = name
  end
  return {
    workspaces = live_workspaces,
    bindings = binds.names(),
    -- Services and projects are not the compositor's to observe: systemd
    -- knows what is running, and reporting a guess here would make the
    -- planner act on one.
    services = {},
    projects = {},
  }
end

---Apply what this runtime owns of a mode: which workspaces are reachable and
---which binding trees are loaded.
---
---Services and projects are deliberately untouched. They belong to the CLI and
---the unit files, which can act on them without a compositor and keep working
---while this one restarts.
---
---Order matters, and it is the order that keeps windows reachable:
---
---  0. validate, so a refused scene set changes nothing (`admit/mode_refused`)
---  1. binding trees, because withdrawing one is instant and costs nothing
---  2. restore, so a workspace this mode admits gets its windows back before
---     anything looks at what is standing where
---  3. hold, emptying the workspaces about to be withdrawn
---  4. withdraw, which now finds them empty and can actually take them away
---  5. place, moving each scene's workspace to its role's output
---     (`admit/scene_monitor`; a missing output falls back to primary)
---
---Holding before withdrawing is not a preference. A workspace disabled while
---its windows stand on it leaves them somewhere the user cannot reach, and the
---registry refuses to do it — so without step 3, step 4 would silently do
---nothing at all.
---@param mode string
---Binding trees declared by a scene, plus a synthetic `drawer:<id>` tree per
---drawer the scene's `drawers` list assigns to it (LEO-363) — the mechanism
---that replaced the hand-named `shelf-ankama`/`shelf-steam`/`shelf-lutris`
---trees: a drawer is admitted exactly like any other scene-owned binding.
---@param declaration table
---@param name string?
---@return table<string, true>
local function scene_binding_set(declaration, name)
  local out = {}
  local scenes = (declaration.base or {}).scenes or {}
  local scene = name and scenes[name]
  if scene and type(scene.bindings) == "table" then
    for _, tree in ipairs(scene.bindings) do
      out[tree] = true
    end
  end
  if scene and type(scene.drawers) == "table" then
    for _, id in ipairs(scene.drawers) do
      out["drawer:" .. id] = true
    end
  end
  return out
end

---Every binding tree that is under any form of admission control: mode
---control (base.bindings) plus scene control (any scene's bindings and
---drawer assignments). A tree named by a scene but not by base.bindings is
---still conditional on the scene.
---@param declaration table
---@return table<string, true>
local function conditional_binding_set(declaration)
  local out = {}
  for _, name in ipairs((declaration.base or {}).bindings or {}) do
    out[name] = true
  end
  for _, scene in pairs((declaration.base or {}).scenes or {}) do
    if type(scene.bindings) == "table" then
      for _, name in ipairs(scene.bindings) do
        out[name] = true
      end
    end
    if type(scene.drawers) == "table" then
      for _, id in ipairs(scene.drawers) do
        out["drawer:" .. id] = true
      end
    end
  end
  return out
end

---Admit or withhold binding trees based on the resolved mode plus the active
---scene. This is separated from the full mode apply so a workspace/scene
---change can recompute binds without re-holding every window.
---@param mode string
---@param scene string? active scene name, if any
---@return string[] disabled tree names
---@return string? error
function M.apply_bindings(mode, scene)
  local declaration, err = M.declaration()
  if not declaration then
    return {}, err
  end

  local desk, resolve_err = desk_for(declaration, mode)
  if not desk then
    return {}, resolve_err
  end

  -- A tree is available if the mode admits it OR the active scene admits it.
  -- That is what "scene-admitted trees follow the active scene as well as the
  -- active mode" means: either context can keep a tree loaded.
  local keeps = {}
  for _, name in ipairs(desk.bindings) do
    keeps[name] = true
  end
  for name in pairs(scene_binding_set(declaration, scene)) do
    keeps[name] = true
  end

  local conditional = conditional_binding_set(declaration)
  local withheld = {}
  for name in pairs(conditional) do
    if not keeps[name] then
      withheld[#withheld + 1] = name
    end
  end
  table.sort(withheld)
  local disabled = binds.admit(withheld)
  for _, name in ipairs(disabled) do
    trace.emit({
      stage = "interact",
      event = "binding_withheld",
      decision = "withhold",
      reason = ("tree %s not admitted by mode %s%s"):format(name, mode, scene and (" or scene " .. scene) or ""),
      mode = mode,
      scene = scene,
    })
  end

  -- The other half of the same decision: a scene-owned tree that IS admitted
  -- because its scene is active gets its own event, so a log reader can see
  -- attachment and withholding as one pair rather than inferring attachment
  -- from the absence of a withheld record.
  if scene then
    for name in pairs(scene_binding_set(declaration, scene)) do
      trace.emit({
        stage = "interact",
        event = "binding_attached",
        decision = "admit",
        reason = ("tree %s admitted by scene %s"):format(name, scene),
        mode = mode,
        scene = scene,
      })
    end
  end

  -- Re-dump the cheatsheet against what is now loaded. A filtered list can
  -- disagree with what the keys actually do; a list derived from the enabled
  -- set cannot.
  local loaded = {}
  for _, name in ipairs(binds.names()) do
    loaded[name] = true
  end
  for _, name in ipairs(disabled) do
    loaded[name] = nil
  end
  pcall(whichkey.dump, loaded)

  applied_scene = scene
  return disabled, nil
end

---The focused workspace's scene name, mirroring `hypr/events/scene.lua`'s
---`M.active` (kept local rather than shared, since that module requires this
---one). Read at mode-apply time so `apply_bindings` admits the scene actually
---focused right now, not "no scene" — otherwise a mode switch onto a scene
---workspace leaves its scene-scoped keys dark until the next
---`workspace.active` event re-admits them (LEO-372).
---@return string?
local function focused_scene_name()
  local ok, ws = pcall(hl.get_active_workspace)
  local name = ok and ws and ws.name
  return name and scene_spec.load()[name] and name or nil
end

---The primary monitor's active workspace name: where a window that must not
---stay where it is goes (an ignored monitor, a hold with no origin).
---@return string?
function M.primary_workspace()
  local host = (rawget(_G, "config") or {}).host or {}
  for _, monitor in ipairs(hl.get_monitors() or {}) do
    if monitor.name == host.primary_monitor and monitor.activeWorkspace then
      return monitor.activeWorkspace.name
    end
  end
  return nil
end

---Log every reachability violation (`admit/unreachable`), and move a held
---window with no origin (which no mode could ever restore) to the primary
---monitor's active workspace.
---@param mode string
---@param admitted table<string, true>
---@param moves table<string, string> address -> destination, dispatched by this apply
---@return integer violations
local function check_reachable(mode, admitted, moves)
  local known = {}
  for _, name in ipairs(workspaces.names()) do
    known[name] = true
  end
  local projected = hold.project(hl.get_windows() or {}, moves)
  local violations = hold.unreachable(projected, admitted, known, hold.record())
  local rescue = M.primary_workspace()
  for _, v in ipairs(violations) do
    local rescued = v.reason == "no_origin" and rescue ~= nil
    if rescued then
      hl.dispatch(
        hl.dsp.window.move({ window = "address:" .. v.address, workspace = "name:" .. rescue, follow = false })
      )
    end
    trace.emit({
      stage = "admit",
      event = "unreachable",
      decision = rescued and "move" or "report",
      reason = v.reason,
      mode = mode,
      window = v.address,
      class = v.class,
      workspace = rescued and rescue or v.workspace,
    })
  end
  return #violations
end

---Re-home every live window a scene admitted by this mode claims but that
---does not stand on that scene's workspace (LEO-353): a claimed window opened
---or was left standing on the wrong scene while nothing admitted claimed it
---yet. Address-targeted, unfollowed, one dispatch per window — the same move
---`hypr/events/scene.lua` uses for a window claimed on open.
---@param mode string
---@param admitted table<string, true> scene/workspace names this mode admits
---@return table<string, string> address -> destination, for the reachability projection
local function collect_home(mode, admitted)
  local specs = scene_spec.load()
  local moved = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    local decision = home.decide(specs, admitted, w)
    if decision.action == "move" and w.address then
      hl.dispatch(hl.dsp.window.move({
        window = "address:" .. w.address,
        workspace = "name:" .. decision.workspace,
        follow = false,
      }))
      if decision.settle then
        -- Same reasoning as the open-time re-home in hypr/events/scene.lua:
        -- a window that was stray-floated before this scene claimed it must
        -- land tiled, not floating, on its own workspace. `action = "off"`,
        -- not a toggle, address-targeted, no focus-dance.
        hl.dispatch(hl.dsp.window.float({ window = "address:" .. w.address, action = "off" }))
      end
      moved[w.address] = decision.workspace
      trace.emit({
        stage = "route",
        event = "collected",
        decision = "move",
        reason = "claimed by " .. decision.workspace,
        mode = mode,
        window = w.address,
        class = w.class,
        workspace = decision.workspace,
      })
    end
  end
  return moved
end

---Whether an apply is running right now; the watcher skips its tick then.
---@return boolean
function M.applying()
  return applying
end

local apply_mode

---@return table? report, string? error
function M.apply(mode)
  if applying then
    return nil, "apply already in progress"
  end
  applying = true
  local ok, report, err = pcall(apply_mode, mode)
  applying = false
  if not ok then
    return nil, tostring(report)
  end
  return report, err
end

---@param mode string
---@return table? report, string? error
apply_mode = function(mode)
  local declaration, err = M.declaration()
  if not declaration then
    return nil, err
  end

  -- Validate before anything moves: a refused mode changes nothing.
  local desk, resolve_err = desk_for(declaration, mode, true)
  if not desk then
    return nil, resolve_err
  end

  local disabled, bind_err = M.apply_bindings(mode, focused_scene_name())
  if bind_err then
    return nil, bind_err
  end

  local admitted = {}
  for _, name in ipairs(desk.workspaces) do
    admitted[name] = true
  end

  -- Give back what this mode admits, before deciding what is occupied.
  -- Every move this apply dispatches, so the invariant below judges where
  -- windows are going rather than where the compositor still reports them.
  local moves = {}
  local restored = 0
  for name in pairs(hold.workspaces()) do
    if admitted[name] then
      local count, addresses = hold.restore(name)
      restored = restored + count
      for _, address in ipairs(addresses) do
        moves[address] = name
      end
    end
  end

  -- Empty what it does not, so the withdrawal below is not refused.
  --
  -- What was emptied is tracked rather than re-read. A move is dispatched, not
  -- performed: asking the compositor what is standing where in the same breath
  -- returns the desk as it was a moment ago, the withdrawal is refused against
  -- stale state, and the mode silently does nothing. Holding moves every
  -- window on the workspace, so a workspace we held from is empty by
  -- construction and does not need confirming.
  local parked, emptied = 0, {}
  for _, name in ipairs(workspaces.names()) do
    if not admitted[name] then
      local count, addresses = hold.hold(name)
      parked = parked + count
      for _, address in ipairs(addresses) do
        moves[address] = hold.HELD
      end
      emptied[name] = true
    end
  end

  local occupied = workspaces.occupied()
  for name in pairs(emptied) do
    occupied[name] = nil
  end

  local withdrawn, refused = workspaces.admit(desk.workspaces, occupied)

  for _, name in ipairs(desk.workspaces) do
    trace.emit({
      stage = "admit",
      event = "workspace_admitted",
      decision = "admit",
      reason = "mode " .. mode,
      mode = mode,
      workspace = name,
    })
  end
  for _, name in ipairs(withdrawn) do
    trace.emit({
      stage = "admit",
      event = "workspace_withdrawn",
      decision = "withhold",
      reason = "mode " .. mode .. " does not admit this workspace",
      mode = mode,
      workspace = name,
    })
  end
  for _, name in ipairs(refused) do
    trace.emit({
      stage = "admit",
      event = "workspace_refused",
      decision = "refuse",
      reason = "occupied",
      mode = mode,
      workspace = name,
    })
  end

  -- Now that the workspaces exist, stand each on its role's output.
  local placements = M.place(desk)

  applied = mode
  applied_desk = desk

  -- Background drawers (LEO-363: Signal, Vesktop, Spotify) start silently now
  -- that the desk's admitted scenes are known. Wrapped in pcall: a launch
  -- failure is logged by `drawer.bring_up` itself and must never fail an
  -- otherwise-successful mode transition.
  pcall(function()
    local drawer = require("hypr.lib.drawer")
    drawer.bring_up(drawer.load(), desk)
  end)

  -- Bring every claimed window home, whatever workspace it drifted to while
  -- nothing admitted claimed it (LEO-353). Folded into `moves` so the
  -- reachability projection below judges where these windows are going.
  for address, workspace in pairs(collect_home(mode, admitted)) do
    moves[address] = workspace
  end

  local unreachable = check_reachable(mode, admitted, moves)

  -- Re-resolve the compositor accent now that the mode has actually
  -- transitioned (LEO-341): `colors.lua` only ran this at config load, so
  -- borders and groupbar kept the previous mode's accent until the next
  -- manual `hyprctl reload`. `apply_colors` reads the palette and mode from
  -- the stores itself, so passing the mode we just applied keeps this call
  -- accurate even if the pointer store's write has not settled to disk yet.
  -- Wrapped in pcall: a missing/broken theme module must not fail a mode
  -- transition that otherwise succeeded.
  pcall(function()
    require("hypr.themes.colors").apply_colors(nil, mode)
  end)

  return {
    mode = mode,
    bindings_disabled = disabled,
    windows_held = parked,
    windows_restored = restored,
    workspaces_withdrawn = withdrawn,
    -- Workspaces that could not be withdrawn because windows still stand on
    -- them. With holding in front of it this should stay empty; a name
    -- appearing here means a window resisted being parked, which is worth
    -- seeing rather than silently working around.
    workspaces_refused = refused,
    placements = placements,
    -- How many windows the reachability invariant flagged (`admit/unreachable`).
    unreachable = unreachable,
  },
    nil
end

---Enter a mode: record it, apply this runtime's half, and hand the rest to the
---command line.
---
---One action drives both halves because the desk is one thing. The compositor
---cannot stop a systemd unit and the CLI cannot disable a keybind, so a mode
---change that only did one of them would leave the desk describing a mode it
---is not in.
---
---The pointer is written FIRST. Every other reader — the shell's pill, the
---notification routing, a later schedule deciding whether it may act — learns
---the mode from it, and writing it after the work would mean a window where
---the desk has changed and nothing can say why.
---
---The services half is spawned rather than waited on. It talks to systemd,
---which can take seconds on a unit that stops slowly, and a compositor that
---blocked on that would drop every keypress meanwhile.
---@param mode string
---@param source string? who is asking: "manual" (default), "timer", "schedule"
---@param until_at string? ISO-8601 expiry; open-ended when nil
---@return table? report, string? error
function M.enter(mode, source, until_at)
  local declaration, err = M.declaration()
  if not declaration then
    return nil, err
  end
  -- Resolve before recording. A mode that cannot resolve must not become the
  -- mode the desk believes it is in.
  local desk, resolve_err = desk_for(declaration, mode)
  if not desk then
    return nil, resolve_err
  end

  local wrote, handle = pcall(store.define, POINTER)
  if wrote then
    pcall(function()
      local pointer = {
        mode = mode,
        source = source or "manual",
        set_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      }
      if until_at then
        pointer["until"] = until_at
        -- Pointer contract: `previous` is the open-ended mode to fall back
        -- to. Layered over a still-running timed mode, carry that mode's
        -- own `previous` forward instead of nesting; otherwise record the
        -- mode in effect now (an expired prior resolves through its own
        -- `previous`). Quickshell's `ModePrecedence.nextPrevious` matches.
        local prior = handle:get() or {}
        if prior["until"] and not expired(prior["until"]) then
          pointer.previous = prior.previous
        else
          pointer.previous = effective_mode(prior)
        end
      end
      -- A full replace, not `set`'s shallow merge: entering an open-ended
      -- mode must drop a previous timed mode's `until`/`previous`, and
      -- `set` would leave them stale since they are simply absent from
      -- `pointer` above.
      handle:update(function()
        return pointer
      end)
    end)
  end

  return M.converge(mode)
end

---Decide and apply what login should do (`hypr/hyprfocus/boot.lua`): enter
---`work`, unless the pointer names a still-running timed mode, which resumes
---instead and keeps its `previous`. Called once from `hyprland.start`
---(`hypr/events/start.lua`) — never from the watcher, which only converges
---on whatever the pointer already says.
---@return table? report, string? error
function M.boot()
  local declaration, err = M.declaration()
  if not declaration then
    return nil, err
  end
  local ok, handle = pcall(store.define, POINTER)
  local pointer = ok and handle:get() or nil
  local action, mode = boot.decide(pointer, declaration.modes or {}, expired)
  if action == "resume" then
    return M.converge(mode)
  end
  return M.enter(mode, "boot")
end

---Converge on a mode the pointer already names, without rewriting it.
---
---The difference from `enter` is exactly the pointer write: a writer outside
---the compositor (the shell's mood centre, a schedule, `seed`) recorded the
---mode already, and rewriting it here would clobber at least the `until`
---expiry and who the pointer says set it. Both halves still run — the desk is
---one thing regardless of who asked.
---
---A mode boundary also clears the submap stack: a submap entered under the
---previous mode may belong to a tree this mode withholds, and the last thing
---a mode change should leave is a menu full of keys that no longer exist (or
---worse, a submap whose binds are disabled and whose way out went with them).
---An empty stack is a no-op, so this is cheap at the entry points that did
---not need it.
---@param mode string
---@return table? report, string? error
function M.converge(mode)
  local report, apply_err = M.apply(mode)
  pcall(function()
    require("hypr.lib.submap").reset()
  end)
  hl.dispatch(hl.dsp.exec_cmd(("%s apply %s"):format(CLI, mode)))
  return report, apply_err
end

---What `apply` would do, without doing it.
---@param mode string
---@return Hyprfocus.Plan?, string? error
function M.plan(mode)
  local declaration, err = M.declaration()
  if not declaration then
    return nil, err
  end
  local desk, resolve_err = desk_for(declaration, mode)
  if not desk then
    return nil, resolve_err
  end
  return plan.plan(desk, M.running()), nil
end

---The mode this runtime last applied, or nil. The watcher's comparison point.
---@return string?
function M.last_applied()
  return applied
end

---The scene whose bindings were last admitted, or nil.
---@return string?
function M.last_applied_scene()
  return applied_scene
end

---The desk this runtime last applied (its `scenes`: `{name, monitor role}`
---placements), or nil before the first apply. The workspace-row binds read
---this rather than re-resolving the mode, so a key press reflects exactly
---what is standing rather than a fresh (and possibly different) resolve.
---@return Hyprfocus.Desk?
function M.applied_desk()
  return applied_desk
end

return M
