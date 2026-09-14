-- The compositor's half of hyprfocus: read the declaration, apply what a mode
-- admits of it.
--
-- This is the seam between the pure modules and the running desk. Everything
-- it calls is decided elsewhere — `resolve` says what a mode means, `plan`
-- says what would change — so the only judgement here is which registries to
-- hand the answer to, and in what order.
--
-- Deliberately NOT wired to any event yet. `apply` is a function that has to
-- be called; nothing calls it. Making a mode change actually move the desk is
-- the step where a mistake is felt, and it should land when someone is
-- watching a reload rather than as a side effect of a config load.
local store = require("hypr.lib.store")
local resolve = require("hypr.hyprfocus.resolve")
local plan = require("hypr.hyprfocus.plan")
local binds = require("hypr.hyprfocus.binds")
local workspaces = require("hypr.hyprfocus.workspaces")
local hold = require("hypr.hyprfocus.hold")
local whichkey = require("hypr.lib.whichkey")

local M = {}

-- The declaration store, seeded from the shell repo on first run and editable
-- at runtime. mtime-cached by the store handle, so reading it per mode change
-- costs nothing when it has not changed.
local DECLARATION = "hyprfocus"
-- The active-mode pointer. Separate from the declaration on purpose: one
-- changes by the minute, the other by configuration.
local POINTER = "focus"

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

  local disabled = binds.admit(desk.bindings)

  -- Re-dump the cheatsheet against what is now loaded. A filtered list can
  -- disagree with what the keys actually do; a list derived from the enabled
  -- set cannot.
  local loaded = { root = true }
  for _, name in ipairs(desk.bindings) do
    loaded[name] = true
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

return M
