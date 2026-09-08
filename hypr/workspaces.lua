-- layout_opts is consumed by hypr/events/layout_opts.lua, not by Hyprland:
-- workspace rules only implement layoutopt:orientation, and hl.workspace_rule
-- rejects the nested per-layout tables outright. Strip it from the rule.
for _, workspace_spec in ipairs(config.host.workspaces.workspace_specs) do
  local rule = {}
  for field, value in pairs(workspace_spec) do
    if field ~= "layout_opts" then
      rule[field] = value
    end
  end
  hl.workspace_rule(rule)
end
