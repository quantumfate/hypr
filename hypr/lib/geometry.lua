-- Pure geometry resolution for workspace_specs, split out of conf/host.lua so
-- it can run under a plain `lua` interpreter in tests/ (no hl, no hostname).
--
-- Two different things get resolved here, and they stay separate for a
-- reason: `monitor_aliases` (primary/secondary -> real output names) comes
-- from the host file (conf/hosts/), because which monitor is "primary" is a
-- property of the
-- machine. `gaps_by_role` comes from a geometry profile keyed by output
-- fingerprint (hypr/lib/profile.lua), because how much air a monitor gets is
-- a property of its panel size, not of which machine it's plugged into.

local M = {}

---Resolves "primary"/"secondary" monitor sentinels in `workspace_specs` to
---real output names, then fills in any gap fields the spec left unset from
---`gaps_by_role` (keyed the same "primary"/"secondary" way). Mutates and
---returns `workspace_specs`.
---
---A spec that already set a gap field keeps it — what it asked for wins over
---any profile. The gaming workspace used to hardcode gaps_out = 0 to sit
---edge-to-edge (LEO-190); it now leaves the fields unset and inherits the
---profile like every other named workspace, keeping only its border/decorate
---preferences explicit.
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

---A CssGap (integer or {top,right,bottom,left} table) -> its left/right pair.
---@param gaps_out integer|table|nil
---@param default_gaps_out integer|table
---@return integer left, integer right
local function left_right(gaps_out, default_gaps_out)
  gaps_out = gaps_out or default_gaps_out
  if type(gaps_out) == "table" then
    local default_table = type(default_gaps_out) == "table" and default_gaps_out or {}
    return gaps_out.left or default_table.left or 0, gaps_out.right or default_table.right or 0
  end
  local n = tonumber(gaps_out) or 0
  return n, n
end

---Per-monitor left/right outer gap, read off *resolved* workspace_specs
---(after `M.resolve` has filled each spec's `monitor` and `gaps_out`) rather
---than from any layout-specific option: workspace layouts are headed to
---`scene`/`columns` only (docs/desktop-model.md), so this must not depend on
---dwindle/master-specific fields. The base gap only — never the solo widen
---(hypr/events/solo_gaps.lua), which is a transient per-workspace correction,
---not part of a monitor's resting geometry.
---
---Specs share a monitor without disagreeing on its gap in every host file
---today, so the first spec seen for a monitor decides it.
---@param workspace_specs HL.WorkspaceRuleSpec[] already resolved by M.resolve
---@param default_gaps_out integer|table the global `general.gaps_out` a spec with no gap falls back to
---@return table<string, {left: integer, right: integer}>
function M.monitor_gaps(workspace_specs, default_gaps_out)
  local monitors = {}
  for _, spec in ipairs(workspace_specs) do
    local name = spec.monitor
    if type(name) == "string" and not monitors[name] then
      local left, right = left_right(spec.gaps_out, default_gaps_out)
      monitors[name] = { left = left, right = right }
    end
  end
  return monitors
end

return M
