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
---Order matters. Binding trees go first because withdrawing one is instant and
---costs nothing; a workspace may refuse to go if it still holds windows, and
---leaving the binds of a half-applied desk enabled is the more confusing of
---the two failures.
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
  local withdrawn, refused = workspaces.admit(desk.workspaces, workspaces.occupied())

  return {
    mode = mode,
    bindings_disabled = disabled,
    workspaces_withdrawn = withdrawn,
    -- Workspaces that could not be withdrawn because windows still stand on
    -- them. Reported rather than forced: the caller holds or moves the windows
    -- and asks again.
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
