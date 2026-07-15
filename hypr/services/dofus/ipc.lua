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

return M
