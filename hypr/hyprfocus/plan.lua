-- What a transition would do, as an ordered list of steps.
--
-- Pure: a desired desk and an observed running state go in, a plan comes out.
-- Nothing is started, stopped, held or dispatched here.
--
-- The separation is the point. The corrective window engine that preceded
-- hyprfocus was untestable because deciding and acting were the same call, so
-- every test needed a fake compositor and every bug needed a live one. A plan
-- that is only data can be printed, diffed, asserted on, and shown to the user
-- before it runs — which is also what makes the announce phase possible at all.
--
-- The plan is computed from a fully RESOLVED desk, never from a mode's deltas.
-- Diffing complete sets is what makes a transition idempotent and free of
-- order-dependence: switching between two modes that both want Obsidian leaves
-- it alone, with no reference counting anywhere.
local resolve = require("hypr.hyprfocus.resolve")

local M = {}

-- Resource kinds, in the order a plan admits them. Workspaces come first
-- because a project opens *onto* one, and services before projects because an
-- app whose backing work is not yet running is an app that looks broken.
local ADMIT_ORDER = { "workspaces", "services", "bindings", "projects" }

-- Revoking runs the other way: let go of the things that depend on something
-- before the thing itself, so nothing is briefly pointing at what just left.
local REVOKE_ORDER = { "projects", "bindings", "services", "workspaces" }

---@class Hyprfocus.Step
---@field action "admit"|"hold"|"retire"|"restore"
---@field kind string resource kind
---@field name string resource name
---@field why string human-readable reason, for the log and the announcement

---@class Hyprfocus.Plan
---@field mode string the mode being entered
---@field steps Hyprfocus.Step[]
---@field takes Hyprfocus.Step[] the subset that takes something away

---@param list string[]
---@return table<string, true>
local function set(list)
  local out = {}
  for _, name in ipairs(list or {}) do
    out[name] = true
  end
  return out
end

---@class Hyprfocus.Running
---@field workspaces string[]
---@field services string[]
---@field bindings string[]
---@field projects string[]
---@field held table<string, string>? resource name -> the mode that holds it

---The steps that take the running desk to the desired one.
---
---A resource present in both desks produces no step at all, which is what
---makes switching between two modes that share a dependency a no-op for that
---dependency rather than a stop-then-start.
---@param desk Hyprfocus.Desk
---@param running Hyprfocus.Running
---@return Hyprfocus.Plan
function M.plan(desk, running)
  local steps, takes = {}, {}

  local function step(action, kind, name, why)
    local entry = { action = action, kind = kind, name = name, why = why }
    steps[#steps + 1] = entry
    if action == "hold" or action == "retire" then
      takes[#takes + 1] = entry
    end
  end

  -- Give up first, then take on. Stopping before starting keeps a transition
  -- from briefly running both desks at once, which on a machine being asked to
  -- save resources is the opposite of what was wanted.
  for _, kind in ipairs(REVOKE_ORDER) do
    local wanted = set(desk[kind])
    for _, name in ipairs(running[kind] or {}) do
      if not wanted[name] then
        local how = resolve.revocation(desk, kind, name)
        step(how, kind, name, ("%s is not admitted by %s"):format(name, desk.mode))
      end
    end
  end

  for _, kind in ipairs(ADMIT_ORDER) do
    local live = set(running[kind])
    for _, name in ipairs(desk[kind]) do
      if not live[name] then
        -- Something this mode admits that a previous mode had parked comes
        -- back as a restore rather than a fresh start, so a held window
        -- returns where it was instead of reopening blank.
        local action = (running.held or {})[name] and "restore" or "admit"
        step(action, kind, name, ("%s is admitted by %s"):format(name, desk.mode))
      end
    end
  end

  return { mode = desk.mode, steps = steps, takes = takes }
end

---Whether a plan would change anything. A transition into the mode already
---running should be silent, not a no-op announcement.
---@param plan Hyprfocus.Plan
---@return boolean
function M.is_empty(plan)
  return #plan.steps == 0
end

---One line per step, for the log and for `hyprfocus plan`.
---@param plan Hyprfocus.Plan
---@return string[]
function M.lines(plan)
  local out = {}
  for i, s in ipairs(plan.steps) do
    out[i] = ("%-7s %-10s %s"):format(s.action, s.kind, s.name)
  end
  return out
end

return M
