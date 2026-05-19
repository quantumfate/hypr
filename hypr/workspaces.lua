local util = require("hypr.lib.util")
---@type Hosts?
local monitor_configs = config.host_configs[util.hostname()]
if monitor_configs then
	for _, workspace_spec in ipairs(config.workspaces.workspace_specs) do
		local workspace = tonumber(workspace_spec.workspace)
		local monitor_name = monitor_configs.monitors[workspace]
		if monitor_name then
			workspace_spec.monitor = monitor_name
			workspace_spec.layout = monitor_configs.monitors[monitor_name].layouts[workspace]
			hl.workspace_rule(workspace_spec)
		end
	end
end
