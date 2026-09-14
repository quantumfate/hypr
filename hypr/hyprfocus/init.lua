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
local binds = require("hypr.hyprfocus.binds")
local workspaces = require("hypr.hyprfocus.workspaces")
local hold = require("hypr.hyprfocus.hold")
local whichkey = require("hypr.lib.whichkey")

local M = {}

--- The mode this runtime last applied successfully, and nil before the first
--- apply. Readers of "what is running" (the watcher) compare against this
--- rather than against what the pointer says, which can drift deliberately
--- (the shell edits it without the compositor running).
local applied = nil

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

---@return string the mode the pointer names, or the resting state
function M.active()
  local ok, handle = pcall(store.define, POINTER)
  if not ok then
    return "neutral"
  end
  return handle:get("mode") or "neutral"
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
---  1. binding trees, because withdrawing one is instant and costs nothing
---  2. restore, so a workspace this mode admits gets its windows back before
---     anything looks at what is standing where
---  3. hold, emptying the workspaces about to be withdrawn
---  4. withdraw, which now finds them empty and can actually take them away
---
---Holding before withdrawing is not a preference. A workspace disabled while
---its windows stand on it leaves them somewhere the user cannot reach, and the
---registry refuses to do it — so without step 3, step 4 would silently do
---nothing at all.
---@param mode string
---@return table? report, string? error
function M.apply(mode)
  local declaration, err = M.declaration()
  if not declaration then
    return nil, err
  end

  local ok, desk = pcall(resolve.resolve, declaration, mode)
  if not ok then
    return nil, tostring(desk)
  end

  -- What this mode takes away, not what it keeps. The base's `bindings` list
  -- names the trees that are UNDER MODE CONTROL; a tree outside that list is
  -- always available, so a gap in the declaration cannot silently remove the
  -- terminal or the way back to another mode.
  local conditional = (declaration.base or {}).bindings or {}
  local keeps = {}
  for _, name in ipairs(desk.bindings) do
    keeps[name] = true
  end
  local withheld = {}
  for _, name in ipairs(conditional) do
    if not keeps[name] then
      withheld[#withheld + 1] = name
    end
  end
  local disabled = binds.admit(withheld)

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

  local admitted = {}
  for _, name in ipairs(desk.workspaces) do
    admitted[name] = true
  end

  -- Give back what this mode admits, before deciding what is occupied.
  local restored = 0
  for name in pairs(hold.workspaces()) do
    if admitted[name] then
      restored = restored + hold.restore(name)
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
      parked = parked + hold.hold(name)
      emptied[name] = true
    end
  end

  local occupied = workspaces.occupied()
  for name in pairs(emptied) do
    occupied[name] = nil
  end

  local withdrawn, refused = workspaces.admit(desk.workspaces, occupied)

  applied = mode

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
---@return table? report, string? error
function M.enter(mode, source)
  local declaration, err = M.declaration()
  if not declaration then
    return nil, err
  end
  -- Resolve before recording. A mode that cannot resolve must not become the
  -- mode the desk believes it is in.
  local ok, desk = pcall(resolve.resolve, declaration, mode)
  if not ok then
    return nil, tostring(desk)
  end
  local _ = desk

  local wrote, handle = pcall(store.define, POINTER)
  if wrote then
    pcall(function()
      handle:set({
        mode = mode,
        source = source or "manual",
        set_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      })
    end)
  end

  return M.converge(mode)
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
  local ok, desk = pcall(resolve.resolve, declaration, mode)
  if not ok then
    return nil, tostring(desk)
  end
  return plan.plan(desk, M.running()), nil
end

---The mode this runtime last applied, or nil. The watcher's comparison point.
---@return string?
function M.last_applied()
  return applied
end

return M
