---@type table<HL.WorkspaceRuleSpec>
local workspace_specs = {
	{
		workspace = "1",
		persistent = true,
		default = true,
		default_name = "code",
	},
	{ workspace = "2", persistent = true, default_name = "study" },
	{ workspace = "3", persistent = true, default_name = "mail" },
	{ workspace = "4", persistent = true, default_name = "media" },
	{
		workspace = "5",
		persistent = true,
		gaps_in = 0,
		gaps_out = 0,
		border_size = 0,
		decorate = false,
		default_name = "gaming",
	},
	{ workspace = "6", persistent = true, default_name = "media" },
}

---@type table<string, table<integer>>
local host_configs = {
	["quantum-laptop"] = { ["eDP-1"] = { 1, 2, 3, 4, 5, 6 } },
	["quantum-desktop"] = { ["DP-1"] = { 1, 2, 3, 4, 5 }, ["DP-2"] = { 6 } },
}

local monitor_configs = host_configs[os.getenv("HOST")]
if monitor_configs then
	for monitor, workspaces in pairs(monitor_configs) do
		for i, _ in ipairs(workspaces) do
			local ws_spec = workspace_specs[i]
			ws_spec.monitor = monitor
			hl.workspace_rule(ws_spec)
		end
	end
end
