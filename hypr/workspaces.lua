for _, workspace_spec in ipairs(config.host.workspaces.workspace_specs) do
  hl.workspace_rule(workspace_spec)
end
