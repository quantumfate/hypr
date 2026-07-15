local common = require("hypr.services.dofus.common")
local notify = require("hypr.lib.notify")

local M = {}

local SWAP_SCRIPT = "dofus_swap.py"
local LOG_DIR = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
local LOG_FILE = LOG_DIR .. "/dofus_swap.log"
local PGREP_PATTERN = "dofus_swap\\.py run"

---@return boolean
local function running()
	local h = io.popen("pgrep -f '" .. PGREP_PATTERN .. "' >/dev/null 2>&1; echo $?")
	if not h then
		-- kill anyway
		return true
	end
	local code = h:read("*n")
	h:close()
	return code == 0
end

---Toggle the dofus_swap.py auto turn-swap detector.
---Kills it if running, else starts it detached. The script reads its roster
---from the shared team.json store itself (and re-reads it live), so no team is
---passed here — the UI/store is the single source of truth.
function M.toggle()
	if running() then
		hl.exec_cmd("pkill -f '" .. PGREP_PATTERN .. "'")
		notify:notify("Swap OFF", 2000, notify.level.INFO)
		return
	end

	local cmd = ("mkdir -p '%s'; setsid '%s' run >> '%s' 2>&1 </dev/null &"):format(
		LOG_DIR,
		SWAP_SCRIPT,
		LOG_FILE
	)
	hl.exec_cmd(cmd)
	notify:notify("Swap ON · " .. common.selected, 2000, notify.level.INFO)
end

return M
