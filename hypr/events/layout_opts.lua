-- Per-workspace layout options.
--
-- Hyprland's layout settings (scrolling.column_width, ...) are globals.
-- Workspace rules accept a layoutopt field, but Hyprland only ever implements
-- layoutopt:orientation, so anything else there is parsed and dropped without
-- a warning. This module emulates the missing feature: it reads layout_opts
-- off the workspace specs' `engine` sub-table (see workspaces.lua for why
-- engine fields never reach the rule) and rewrites the matching globals around
-- the moments a layout reads them.
--
-- A spec declares options either flat, for its own layout:
--
--   { workspace = "1", layout = "scrolling",
--     engine = { layout_opts = { column_width = 0.67 } } }
--
-- or keyed by layout, for a workspace whose layout is cycled at runtime
-- (SUPER+x -> e), so each layout gets its own settings on that workspace:
--
--   { workspace = "1", layout = "scrolling", engine = { layout_opts = {
--       scrolling = { column_width = 0.67 },
--   } } }
--
-- Options are only read by a layout when it (re)tiles, so these take effect on
-- the next window open or resize; already-tiled windows keep their geometry.

-- Layout name -> config namespace holding its options. Scene and columns own
-- their geometry directly and have no config namespace here.
local namespaces = {
  scrolling = "scrolling",
}

---Full config key for one layout option, validated against the running
---Hyprland so a typo fails at config load instead of being silently ignored.
---@param layout string
---@param opt string
---@param where string context for the error message
---@return string
local function config_key(layout, opt, where)
  local namespace = assert(namespaces[layout], ("%s: no layout options exist for layout '%s'"):format(where, layout))
  local key = namespace .. "." .. opt
  local _, err = hl.get_config(key)
  assert(not err, ("%s: %s"):format(where, tostring(err)))
  return key
end

-- overrides[workspace][layout] = { [config key] = value }
local overrides = {}
-- Every key any workspace overrides, so a workspace that does not set one can
-- be restored to the global instead of inheriting the last workspace's value.
local touched = {}

---@param spec table a host workspace_spec
local function collect(spec)
  local opts = spec.engine and spec.engine.layout_opts
  if not opts or not next(opts) then
    return
  end
  local where = ("workspace '%s' layout_opts"):format(tostring(spec.workspace))

  -- Nested (keyed by layout) or flat (this workspace's own layout)? Layout
  -- names and option names do not overlap, so the first key decides.
  local by_layout = opts
  if not namespaces[next(opts)] then
    by_layout = { [assert(spec.layout, ("%s: flat layout_opts needs a layout on the spec"):format(where))] = opts }
  end

  local per_workspace = {}
  for layout, layout_options in pairs(by_layout) do
    assert(type(layout_options) == "table", ("%s: expected a table of options for '%s'"):format(where, layout))
    local resolved = {}
    for opt, value in pairs(layout_options) do
      local key = config_key(layout, opt, where)
      resolved[key] = value
      touched[key] = true
    end
    per_workspace[layout] = resolved
  end
  overrides[tostring(spec.workspace)] = per_workspace
end

for _, spec in ipairs(config.host.workspaces.workspace_specs) do
  collect(spec)
end

-- Baseline for each touched key, captured the first time we override it. Read
-- lazily rather than at load: hypr/init.lua requires events before layouts, so
-- the layout modules have not applied their own defaults yet at this point.
local baseline = {}

---@param key string
---@return any
local function baseline_of(key)
  if baseline[key] == nil then
    baseline[key] = hl.get_config(key)
  end
  return baseline[key]
end

---Nested config table from flat "namespace.option" keys, the shape hl.config
---expects: { scrolling = { column_width = 0.6 } }.
---@param values table<string, any>
---@return table
local function nest(values)
  local out = {}
  for key, value in pairs(values) do
    local namespace, opt = key:match("^(.-)%.(.+)$")
    out[namespace] = out[namespace] or {}
    out[namespace][opt] = value
  end
  return out
end

---@param ws HL.Workspace|nil workspace to configure for; defaults to the focused one
local function apply(ws)
  ws = ws or hl.get_active_special_workspace() or hl.get_active_workspace()
  if not ws then
    return
  end
  -- Specs key off the config string ("1"), which is the id for numbered
  -- workspaces and the name for named/special ones. tiled_layout rather than
  -- the spec's layout, so cycling a workspace's layout picks up its options.
  local for_workspace = overrides[tostring(ws.id)] or overrides[ws.name] or {}
  local active = for_workspace[ws.tiled_layout] or {}

  local values = {}
  for key in pairs(touched) do
    local override = active[key]
    values[key] = override ~= nil and override or baseline_of(key)
  end
  if next(values) then
    hl.config(nest(values))
  end
end

-- Focusing a workspace on another monitor emits monitor.focused without a
-- workspace.active, so both are needed to cover every switch. Those two only
-- keep the globals warm, though: a layout reads these options when it tiles,
-- so the window.open_early handler is the one that decides the geometry.
hl.on("workspace.active", function()
  apply()
end)
hl.on("monitor.focused", function()
  apply()
end)
hl.on("workspace.special_active", function()
  apply()
end)
-- The opening window carries the workspace it is about to tile into, which is
-- not always the focused one: focusing an empty workspace leaves the active
-- monitor (and so hl.get_active_workspace) pointing at the previous one, and a
-- window rule can send this window elsewhere entirely.
---@param w HL.Window
hl.on("window.open_early", function(w)
  apply(w and w.workspace)
end)
