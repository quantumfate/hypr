-- Host selection and finalization: this module turns the shared base
-- (conf/base.lua) plus one host file (conf/hosts/) into the `config` global
-- every hypr/* module reads. The table shapes those modules see do not change
-- here — only who builds them does.
--
-- A host file is data, keyed by hostname; when no file exists for this
-- machine, conf/hosts/default.lua takes over ("assume it works" is the
-- fallback contract). A file that EXISTS but errors is never masked by the
-- fallback: it is a broken machine, not a missing one — require() raises and
-- Hyprland reports it.
--
-- `build()` keeps host files terse by filling the defaults a workspace spec
-- almost always wants (plain workspaces are persistent and run the scene
-- layout; specials are neither), then resolves the geometry half: the
-- primary/secondary monitor sentinels, the fingerprint profile and its gaps.
local geometry = require("hypr.lib.geometry")
local profile = require("hypr.lib.profile")
local Store = require("hypr.lib.store")

local M = {}

-- Mirrors hypr/conf.lua's `general.gaps_out`: the fallback for a monitor role
-- geometry_profiles never overrides. Read live via hl.get_config where
-- possible so a future edit to conf.lua can't silently drift from this
-- default; this literal only backs the case hl has no value loaded yet.
local DEFAULT_GAPS_OUT = { top = 8, right = 40, bottom = 40, left = 40 }

-- LEO-340: the bar's side insets follow each monitor's tiled outer gap, base
-- gap only (never the solo widen from hypr/events/solo_gaps.lua). Quickshell
-- reads this store and falls back to Theme.barInset*2 when a monitor has no
-- entry.
local geometry_store = Store.define("geometry")

---@param hostname string
---@return Hosts
local function host_table(hostname)
  local name = "conf.hosts." .. hostname
  if package.searchpath(name, package.path) then
    -- Captured first: require declares a two-value surface, and a module
    -- returning nothing is a broken file, not a missing machine.
    local host = require(name)
    ---@cast host Hosts
    return host
  end
  local host = require("conf.hosts.default")
  return host
end

---Fill the defaults a workspace spec leaves unset. A special's lifetime is
---its own — opening it and leaving is what toggling gives — so `persistent`
---belongs only to plain workspaces. A plain spec with no `monitor` sits on
---the primary: "primary" is spelled as a sentinel here so geometry.resolve()
---below rewrites it to the host's real output name.
---@param specs HL.WorkspaceRuleSpec[]
local function fill_spec_defaults(specs)
  for _, spec in ipairs(specs) do
    local plain = not tostring(spec.workspace):find(":", 1, true)
    if spec.layout == nil then
      spec.layout = "scene"
    end
    if plain then
      if spec.persistent == nil then
        spec.persistent = true
      end
      if spec.monitor == nil then
        spec.monitor = "primary"
      end
    end
  end
end

-- The hostname is resolved once, here; every consumer reads `config.host.*`
-- without ever computing the name itself. Required per build, not at this
-- file's require time: tests reload `hypr.lib.util`, and a captured handle
-- would keep reading the machine's real name.
function M.build()
  local config = require("conf.base")
  _G.config = config
  config.__index = config

  -- A machine whose name cannot be computed has no host files to pick;
  -- config/hosts/default.lua is exactly the desk for that.
  local hostname = assert(require("hypr.lib.util").hostname())
  config.host = host_table(hostname)
  fill_spec_defaults(config.host.workspaces.workspace_specs)

  -- Geometry is decided by output fingerprint rather than hostname — see
  -- hypr/lib/profile.lua's header for why. `resolve()` honors a manual
  -- SUPER Space w m override over the live fingerprint.
  config.profile = profile.resolve()
  profile.publish(config.profile)

  geometry.resolve(
    config.host.workspaces.workspace_specs,
    { primary = config.host.primary_monitor, secondary = config.host.secondary_monitor },
    (config.geometry_profiles[config.profile] or {}).gaps_by_monitor
  )

  geometry_store:put({
    monitors = geometry.monitor_gaps(
      config.host.workspaces.workspace_specs,
      hl.get_config("general.gaps_out") or DEFAULT_GAPS_OUT
    ),
  })
end

return M
