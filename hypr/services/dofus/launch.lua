local M = {}

M.enabled = false

local notify = require("hypr.lib.notify")
local common = require("hypr.services.dofus.common")
M.counter = 1
M.launch_cmd = 'xdotool set_window --name "Dofus %s" "$(xdotool search --pid %s)"'

-- Launch names windows against the *currently selected* team (read live at each
-- window.open), so the flow is: mod+d -> d (enable) -> branch into a team submap
-- -> its members get named in order as clients open. See common.team().

function M:reset_counter()
	self.counter = 1
	notify:notify("Dofus Launch Counter Reset", 2000, notify.level.INFO)
end

function M:increment_counter()
	self.counter = self.counter + 1
end

function M:toggle_enable()
	if self.enabled then
		self.enabled = false
		notify:notify("Dofus Launch Disabled", 2000, notify.level.INFO)
	else
		self.enabled = true
		notify:notify("Dofus Launch Enabled", 2000, notify.level.INFO)
	end
end

hl.on(
	"window.open",
	---@param w HL.Window
	function(w)
		if not M.enabled then
			return
		end

		-- Selected team, read live so branching into a team submap after enabling
		-- launch names its clients (order = list order).
		local team = common.team()

		if w.class == "Dofus.x64" and M.counter <= #team then
			local cmd = M.launch_cmd:format(team[M.counter], w.pid)
			hl.dispatch(hl.dsp.exec_raw(cmd))
			M:increment_counter()
		end

		if M.counter > #team then
			M:reset_counter()
			M:toggle_enable()
		end
	end
)

return M
