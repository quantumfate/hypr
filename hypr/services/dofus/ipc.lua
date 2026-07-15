-- Thin wrapper over the Quickshell IPC surface (services in the quickshell
-- repo: DofusState -> target "dofus", DofusTeam -> target "dofusPanel").
-- Commands (not state) go over IPC; state goes through the shared team.json
-- store. Calls are fire-and-forget so they never block the compositor thread.
local M = {}

local BASE = "qs -c quantumfate ipc call"

---@param args string ipc "target function [arg...]"
local function call(args)
	hl.exec_cmd(BASE .. " " .. args)
end

---Select the active team in the running UI (instant; the store write in
---common.select is the durable truth, this just pushes it without waiting for
---the file watch).
---@param team string
function M.select(team)
	call("dofus select " .. team)
end

---Control the team panel window. cmd = "show" | "hide" | "toggle".
---@param cmd string
function M.panel(cmd)
	call("dofusPanel " .. cmd)
end

---Ask the UI to re-read team.json from disk now.
function M.reload()
	call("dofus reload")
end

return M
