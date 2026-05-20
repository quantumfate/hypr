local util = require("hypr.lib.util")
local host = util.host_config()
if host then
	for _, workspace_spec in ipairs(host.workspaces.workspace_specs) do
		hl.workspace_rule(workspace_spec)
	end
end
