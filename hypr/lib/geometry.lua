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

---One side of a CssGap (integer or {top,right,bottom,left} table) as a number.
---A table's unnamed side is a real 0; `nil` falls to `fallback` first.
---@param gap integer|table|nil
---@param which "top"|"right"|"bottom"|"left"
---@param fallback integer|table|nil
---@return integer
local function side(gap, which, fallback)
  local value = gap == nil and fallback or gap
  if value == nil then
    return 0
  end
  if type(value) == "table" then
    return value[which] or 0
  end
  return tonumber(value) or 0
end

---Per-monitor left/right outer gap: a MONITOR's resting geometry, not any one
---workspace's. The base gap only — never the scene layout's own solo widen,
---which is a transient per-workspace correction.
---
---The geometry profile is the answer where it has one (`role_gaps` keyed
---"primary"/"secondary", resolved through `aliases` to output names), because
---a single workspace that declares its own tighter gaps — `reference` and
---`media` do — must not redefine the whole monitor for every other surface
---reading this map. Only a monitor the profile does not name falls back to
---the resolved specs, first spec seen wins.
---@param workspace_specs HL.WorkspaceRuleSpec[] already resolved by M.resolve
---@param default_gaps_out integer|table the global `general.gaps_out` a spec with no gap falls back to
---@param role_gaps table<string, table>? the profile's `gaps_by_monitor`
---@param aliases table<string, string>? {primary=<output>, secondary=<output>}
---@return table<string, {left: integer, right: integer}>
function M.monitor_gaps(workspace_specs, default_gaps_out, role_gaps, aliases)
  local monitors = {}
  for role, gaps in pairs(role_gaps or {}) do
    local name = (aliases or {})[role]
    if type(name) == "string" then
      local left, right = left_right(gaps.gaps_out, default_gaps_out)
      monitors[name] = { left = left, right = right }
    end
  end
  for _, spec in ipairs(workspace_specs) do
    local name = spec.monitor
    if type(name) == "string" and not monitors[name] then
      local left, right = left_right(spec.gaps_out, default_gaps_out)
      monitors[name] = { left = left, right = right }
    end
  end
  return monitors
end

---The host workspace-spec for a workspace, keyed by `default_name` — the same
---lookup hypr/scene/provider.lua's `host_gaps` (and the deck provider's twin)
---makes for one scene's middle rung. Two workspaces sharing a monitor may tile
---at different gaps, so this is per workspace, never the first spec of a
---monitor.
---@param workspace_specs HL.WorkspaceRuleSpec[] already resolved by M.resolve
---@param default_name string
---@return HL.WorkspaceRuleSpec?
local function spec_for(workspace_specs, default_name)
  for _, spec in ipairs(workspace_specs or {}) do
    if spec.default_name == default_name then
      return spec
    end
  end
  return nil
end

---The FINAL per-workspace outer gap hyprland tiles at, on all four sides —
---the distance from the monitor's edge to the scene's outermost visible
---window — published to the `geometry` store for the bar that opts in
---(`bar_follows_scene_gaps`) to subscribe. Quickshell never mirrors or
---re-derives a gap; the whole sum is assembled here, once.
---
---Four things stack between the monitor edge and that window, and this folds
---all of them, per side:
---  1. the workspace rule's `gaps_out`, which the compositor subtracts from the
---     monitor work area BEFORE the layout runs (`CSpace::recheckWorkArea`), so
---     it lands OUTSIDE the layout's own frame;
---  2. the layout's own gap, walked up the engine's ladder (provider.lua
---     `gaps`, with the deck provider's twin): scene `gaps_out` first, then the
---     host workspace-spec keyed by `default_name`, then the compositor's
---     global — spilled the same way every scene's layout folds a gap
---     (`layout.lua`'s `sides`, which `deck.lua` now shares too, LEO-421): an
---     unnamed side is a real 0, never a fall-through to the next rung;
---  3. the workspace rule's `gaps_in`, which `CWindowTarget::updatePos` adds to
---     a side the layout did NOT leave flush with the work area — a side the
---     layout did leave flush (its gap is 0) keeps the work-area edge;
---  4. the window's border, which the same function always reserves.
---@param scenes table<string, Scene.Spec> declared scenes keyed by default_name
---@param workspace_specs HL.WorkspaceRuleSpec[] already resolved by M.resolve
---@param default_gaps_out integer|table? the global `general.gaps_out`
---@param inner { gaps_in: integer|table?, border: integer }? the compositor's workspace-rule gap and border
---@return table<string, {top: integer, right: integer, bottom: integer, left: integer}>
function M.resolved_gaps(scenes, workspace_specs, default_gaps_out, inner)
  inner = inner or {}
  local border = inner.border or 0
  local out = {}
  for name, scene in pairs(scenes or {}) do
    local spec = spec_for(workspace_specs, name)
    local spec_out = spec and spec.gaps_out
    local layout_gap = scene.gaps_out or spec_out or default_gaps_out

    out[name] = {}
    for _, which in ipairs({ "top", "right", "bottom", "left" }) do
      local own = side(layout_gap, which, 0)
      -- Add back what the compositor removed or is about to add: the
      -- workspace gaps_out came out of ctx.area; gaps_in and the border go
      -- on to any side the layout left inset, while a flush side keeps the
      -- work-area edge.
      local ws_out = side(spec_out, which, default_gaps_out)
      local ws_in = side(spec and spec.gaps_in, which, inner.gaps_in)
      out[name][which] = ws_out + own + (own > 0 and ws_in or 0) + border
    end
  end
  return out
end

return M
