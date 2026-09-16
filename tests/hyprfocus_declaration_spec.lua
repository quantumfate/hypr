-- The shipped hyprfocus declaration and every host's workspace names, pinned
-- against each other (LEO-337).
--
-- The declaration and the host configs are edited independently — one in the
-- quickshell sibling repo, one here — and nothing else checks that they
-- still agree. When they drift, the resolver's unknown-name rule refuses a
-- mode transition at runtime (fixture `07-unknown-name-refuses.json`), which
-- is the failure this spec exists to catch before it reaches a desk: every
-- workspace the declaration names (`base.workspaces`, every mode's
-- `workspaces.only`/`remove`) must exist as a `default_name` on every host,
-- and every `default_name` a host declares must be named somewhere in the
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
    local spec = dofile(path)
    local names = {}
    for _, rule in ipairs((spec.workspaces or {}).workspace_specs or {}) do
      if rule.default_name then
        names[rule.default_name] = true
      end
    end
    hosts[host] = names
  end
  p:close()
  return hosts
end

---Every workspace name the declaration mentions anywhere: the base set plus
---whatever each mode's `only`/`remove` delta names — a delta may reference a
---workspace the base itself forgot to list, and that is exactly the drift
---this spec is for.
---@param declaration table
---@return table<string, boolean>
local function declared_workspaces(declaration)
  local names = {}
  for _, name in ipairs((declaration.base or {}).workspaces or {}) do
    names[name] = true
  end
  for _, mode in pairs(declaration.modes or {}) do
    local delta = mode.workspaces
    if delta then
      for _, name in ipairs(delta.only or {}) do
        names[name] = true
      end
      for _, name in ipairs(delta.remove or {}) do
        names[name] = true
      end
      for _, name in ipairs(delta.add or {}) do
        names[name] = true
      end
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
