-- Pure geometry resolution for workspace_specs, split out of hyprland.lua so
-- it can run under a plain `lua` interpreter in tests/ (no hl, no hostname).
--
-- Two different things get resolved here, and they stay separate for a
-- reason: `monitor_aliases` (primary/secondary -> real output names) comes
-- from host_configs, because which monitor is "primary" is a property of the
-- machine. `gaps_by_role` comes from a geometry profile keyed by output
-- fingerprint (hypr/lib/profile.lua), because how much air a monitor gets is
-- a property of its panel size, not of which machine it's plugged into.

local M = {}

---Resolves "primary"/"secondary" monitor sentinels in `workspace_specs` to
---real output names, then fills in any gap fields the spec left unset from
---`gaps_by_role` (keyed the same "primary"/"secondary" way). Mutates and
---returns `workspace_specs`.
---
---A spec that already set a gap field (the gaming workspace's explicit
---gaps_out = 0) is never touched — "asked for no gaps" wins over any profile.
---@param workspace_specs HL.WorkspaceRuleSpec[]
---@param monitor_aliases table<string, string> {primary=..., secondary=...}
---@param gaps_by_role table<string, table>? {primary={gaps_in=,gaps_out=}, secondary={...}}
---@return HL.WorkspaceRuleSpec[]
function M.resolve(workspace_specs, monitor_aliases, gaps_by_role)
  gaps_by_role = gaps_by_role or {}
  for _, spec in ipairs(workspace_specs) do
    local role = spec.monitor
    if role == "primary" or role == "secondary" then
      spec.monitor = assert(
        monitor_aliases[role],
        "workspace " .. tostring(spec.workspace) .. " uses '" .. role .. "' but host has no such monitor"
      )
      for key, value in pairs(gaps_by_role[role] or {}) do
        if spec[key] == nil then
          spec[key] = value
        end
      end
    end
  end
  return workspace_specs
end

return M
