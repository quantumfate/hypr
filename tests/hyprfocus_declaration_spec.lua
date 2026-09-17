-- The shipped hyprfocus declaration and every host's workspace names, pinned
-- against each other (LEO-337).
--
-- The declaration and the host configs are edited independently — one in the
-- quickshell sibling repo, one here — and nothing else checks that they
-- still agree. When they drift, the resolver's unknown-name rule refuses a
-- mode transition at runtime (fixture `07-unknown-name-refuses.json`), which
-- is the failure this spec exists to catch before it reaches a desk: every
-- workspace the declaration names (every `base.scenes` catalog entry and every
-- mode's `scenes[].name`) must exist as a `default_name` on every host, and
-- every `default_name` a host declares must be named somewhere in the
-- declaration.
local t = require("tests.harness")
local json = require("hypr.lib.json")

local declaration_path = (
  debug.getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/../../quickshell/assets/hyprfocus.default.json"
)

---Every host file's declared workspace names, keyed by host.
---@return table<string, table<string, boolean>>
local function host_workspaces()
  local hosts = {}
  local p = assert(io.popen("ls conf/hosts/*.lua 2>/dev/null"))
  for path in p:lines() do
    local host = path:match("([^/]+)%.lua$")
    -- The e2e host is a nested-compositor fixture with its own tiny workspace
    -- set, not a machine the shipped declaration is written for.
    if host == "e2e" then
      goto continue
    end
    local spec = dofile(path)
    local names = {}
    for _, rule in ipairs((spec.workspaces or {}).workspace_specs or {}) do
      if rule.default_name then
        names[rule.default_name] = true
      end
    end
    hosts[host] = names
    ::continue::
  end
  p:close()
  return hosts
end

---Every workspace name the declaration mentions anywhere: the scene catalog
---plus every mode's scene set — a mode may list a scene the catalog forgot,
---and that is exactly the drift this spec is for.
---@param declaration table
---@return table<string, boolean>
local function declared_workspaces(declaration)
  local names = {}
  for name in pairs((declaration.base or {}).scenes or {}) do
    names[name] = true
  end
  for _, mode in pairs(declaration.modes or {}) do
    for _, placement in ipairs(mode.scenes or {}) do
      names[placement.name] = true
    end
  end
  return names
end

local function read_file(path)
  local handle = io.open(path, "r")
  if not handle then
    return nil
  end
  local content = handle:read("*a")
  handle:close()
  return content
end

t.describe("the shipped declaration agrees with every host", function()
  local raw = read_file(declaration_path)
  if not raw then
    t.it("skip: sibling quickshell checkout not found at " .. declaration_path, function() end)
    return
  end
  local declaration = json.decode(raw)
  local declared = declared_workspaces(declaration)

  for host, defaults in pairs(host_workspaces()) do
    t.it(host .. ": every declared workspace exists as a default_name", function()
      local missing = {}
      for name in pairs(declared) do
        if not defaults[name] then
          table.insert(missing, name)
        end
      end
      table.sort(missing)
      t.eq("", table.concat(missing, ","), "workspaces named in the declaration but not on " .. host)
    end)

    t.it(host .. ": every default_name is named in the declaration", function()
      local missing = {}
      for name in pairs(defaults) do
        if not declared[name] then
          table.insert(missing, name)
        end
      end
      table.sort(missing)
      t.eq("", table.concat(missing, ","), host .. "'s workspaces not named anywhere in the declaration")
    end)
  end
end)

-- The declaration's `base.scenes` is the only scene table (docs/scenes.md,
-- "Source of truth"): the engine normalizes it, and no second copy returns.
t.describe("base.scenes is the single scene table", function()
  t.it("no seed module or scenes store reader remains", function()
    t.eq(nil, io.open("hypr/scene/defaults.lua", "r"), "hypr/scene/defaults.lua is retired")
    local p = assert(io.popen([[grep -rln 'define("scenes")\|scene\.defaults' hypr conf 2>/dev/null]]))
    local hits = {}
    for path in p:lines() do
      -- The loader names the legacy store only to fold and retire it once.
      if path ~= "hypr/scene/spec.lua" then
        hits[#hits + 1] = path
      end
    end
    p:close()
    t.eq("", table.concat(hits, ","), "a second scene table reader")
  end)

  local raw = read_file(declaration_path)
  if not raw then
    return
  end

  t.it("the shipped scenes normalize with no ambiguous block classes", function()
    local declaration = json.decode(raw)
    package.loaded["hypr.scene.spec"] = nil
    package.loaded["hypr.lib.store"] = {
      define = function()
        return {
          get = function()
            return declaration
          end,
          put = function() end,
        }
      end,
    }
    local spec_lib = require("hypr.scene.spec")
    local ambiguous = {}
    for name, scene in pairs(spec_lib.load()) do
      if #spec_lib.ambiguous_classes(scene) > 0 then
        ambiguous[#ambiguous + 1] = name
      end
    end
    package.loaded["hypr.scene.spec"] = nil
    package.loaded["hypr.lib.store"] = nil
    t.eq("", table.concat(ambiguous, ","))
  end)
end)
