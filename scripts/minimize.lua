local helper = require("scripts.helper")
M = {}
M.worspace = "magic"
function M:toggle_minimize()
	if
		helper.any(function(workspace)
			return workspace.name == "special:" .. self.worspace
		end, hl.get_workspaces())
	then
		-- special:magic exists -> show it, pull active window back to current workspace
		hl.dispatch(hl.dsp.workspace.toggle_special(self.worspace))
	else
		-- special:magic absent -> send active window to it silently
		hl.dispatch(hl.dsp.window.move({ workspace = "special:" .. self.worspace }))
	end
end

return M
