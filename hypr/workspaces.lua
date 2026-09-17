-- A workspace spec's top level *is* the Hyprland workspace rule; the engine's
-- own fields are not Hyprland's and must not leak into it. They live under one
-- `engine` sub-table, so the exclusion is structural rather than a maintained
-- field list:
--   engine.layout_opts -- consumed by hypr/events/layout_opts.lua; workspace
--     rules only implement layoutopt:orientation, and hl.workspace_rule rejects
--     the nested per-layout tables outright.
-- A spec with a `default_name` keys its rule on that name, not on the id. The
-- rest of the environment addresses workspaces by name (binds, hold restore,
-- window rules, the scene actuator), and when a mode withdrew an id-keyed
-- workspace, a later `name:code` dispatch spawned an auto-named duplicate that
-- inherited no rule and fell back to the default layout. A name-keyed rule
-- matches both the id-backed workspace and any named duplicate.
-- The handle is kept, not discarded: it carries `set_enabled`, which is how a
-- mode withdraws a workspace and brings it back without a reload. This is the
-- only place workspace rules are created, so recording here needs no wrapper.
local registry = require("hypr.hyprfocus.workspaces")
local layout = require("hypr.lib.layout")

for _, workspace_spec in ipairs(config.host.workspaces.workspace_specs) do
  local rule = {}
  for field, value in pairs(workspace_spec) do
    if field ~= "engine" then
      rule[field] = value
    end
  end
  if workspace_spec.default_name and not tostring(workspace_spec.workspace):find(":", 1, true) then
    rule.workspace = "name:" .. workspace_spec.default_name
  end
  rule.layout = layout.rule_layout(rule.layout)
  registry.record(workspace_spec.default_name, hl.workspace_rule(rule))
end
