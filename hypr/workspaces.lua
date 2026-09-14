-- A workspace spec's top level *is* the Hyprland workspace rule; the engine's
-- own fields are not Hyprland's and must not leak into it. They live under one
-- `engine` sub-table, so the exclusion is structural rather than a maintained
-- field list:
--   engine.layout_opts -- consumed by hypr/events/layout_opts.lua; workspace
--     rules only implement layoutopt:orientation, and hl.workspace_rule rejects
--     the nested per-layout tables outright.
--   engine.solo_gaps   -- consumed by hypr/events/solo_gaps.lua as the framing
--     opt-out.
for _, workspace_spec in ipairs(config.host.workspaces.workspace_specs) do
  local rule = {}
  for field, value in pairs(workspace_spec) do
    if field ~= "engine" then
      rule[field] = value
    end
  end
  hl.workspace_rule(rule)
end
