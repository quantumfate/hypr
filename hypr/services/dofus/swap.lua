local common = require("hypr.services.dofus.common")
local notify = require("hypr.lib.notify")

local M = {}

local SCRIPTS_DIR = os.getenv("HOME") .. "/Projects/gitlab/quantumfate/dofus-scripts"
local SWAP_SCRIPT = SCRIPTS_DIR .. "/dofus_swap.py"
local LOG_DIR = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
local LOG_FILE = LOG_DIR .. "/dofus_swap.log"
local PGREP_PATTERN = "dofus_swap\\.py run"

---@return boolean
local function running()
	local ok = os.execute("pgrep -f '" .. PGREP_PATTERN .. "' >/dev/null 2>&1")
	return ok == true or ok == 0
end

---Toggle the dofus_swap.py auto turn-swap detector for a team.
---Kills it if running, else starts it detached with the team's character names.
---@param team string[]? character names (default: selected team)
function M.toggle(team)
	team = team or common.team()

	if running() then
		hl.exec_cmd("pkill -f '" .. PGREP_PATTERN .. "'")
		notify:notify("Swap OFF", 2000, notify.level.INFO)
		return
	end

	local args = {}
	for _, name in ipairs(team) do
		args[#args + 1] = "'" .. name .. "'"
	end

	local cmd = ("mkdir -p '%s'; setsid '%s' run --characters %s >> '%s' 2>&1 </dev/null &"):format(
		LOG_DIR,
		SWAP_SCRIPT,
		table.concat(args, " "),
		LOG_FILE
	)
	hl.exec_cmd(cmd)
	notify:notify("Swap ON · " .. common.selected, 2000, notify.level.INFO)
end

return M
