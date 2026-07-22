-- Dofus-specific view of the Quickshell IPC surface (DofusState -> target
-- "dofus", DofusTeam -> target "dofusPanel"). Commands go over IPC; state goes
-- through the shared team.json store. Built on the generic hypr/lib/qs helper.
local qs = require("hypr.lib.qs")

local M = {}

---Select the active team in the running UI (instant; the store write in
---common.select is the durable truth, this just pushes it without waiting for
---the file watch).
---@param team string
function M.select(team)
  qs.call("dofus", "select", team)
end

---Control the team panel window. cmd = "show" | "hide" | "toggle".
---@param cmd string
function M.panel(cmd)
  qs.call("dofusPanel", cmd)
end

---Ask the UI to re-read team.json from disk now.
function M.reload()
  qs.call("dofus", "reload")
end

---Push a character's class into the running UI (instant). The durable write is
---common.set_class; this just pushes without waiting for the file watch. Pass
---cls = "" to clear.
---@param name string character name
---@param cls string class key ("" clears)
function M.set_class(name, cls)
  qs.call("dofus", "setClass", name, cls or "")
end

---Notify the class key currently set for a character.
---@param name string character name
function M.class_of(name)
  qs.notify("Dofus class", "dofus", "classOf " .. ("%q"):format(name))
end

---Open/close the team selector widget. cmd = "show" | "hide" | "toggle".
---@param cmd string
function M.team_selector(cmd)
  qs.call("teamSelector", cmd)
end

---Open/close the class assigner widget. cmd = "show" | "hide" | "toggle".
---@param cmd string
function M.class_assigner(cmd)
  qs.call("classAssigner", cmd)
end

return M
