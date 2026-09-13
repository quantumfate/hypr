-- Some spec fields are ours, not Hyprland's, and must be stripped from the
-- rule or Hyprland rejects it as an unknown field:
--   layout_opts -- consumed by hypr/events/layout_opts.lua; workspace rules
--     only implement layoutopt:orientation, and hl.workspace_rule rejects the
--     nested per-layout tables outright.
--   solo_gaps   -- consumed by hypr/events/solo_gaps.lua as the framing opt-out.
local engine_only_fields = {
  layout_opts = true,
  solo_gaps = true,
}

for _, workspace_spec in ipairs(config.host.workspaces.workspace_specs) do
  local rule = {}
  for field, value in pairs(workspace_spec) do
    if not engine_only_fields[field] then
      rule[field] = value
    end
  end
  hl.workspace_rule(rule)
end
