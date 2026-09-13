--- Runs every tests/*_spec.lua and exits non-zero on failure.
---
---     lua tests/run.lua
---     TEST_SPECS=tests/json_spec.lua lua tests/run.lua
---
--- One Lua process for the whole suite (unlike the nvim config's per-spec
--- process harness): hypr/lib/* is pure and has no compositor/editor state
--- that could bleed between specs, so the only isolation that matters is
--- resetting `_G.hl` and re-requiring hypr.* modules fresh per spec, which
--- this does directly rather than paying for a subprocess per spec.
package.path = package.path .. ";./?.lua"

local t = require("tests.harness")

---@param path string
local function spec_name(path)
  return (path:match("([^/]+)%.lua$"))
end

---Modules under test cache state at require-time (store.lua's ROOT, submap.lua's
---stack, ...) so a spec that ran earlier must not leave any hypr.* module loaded.
local function reset_module_cache()
  for k in pairs(package.loaded) do
    if k == "hypr" or k:match("^hypr%.") then
      package.loaded[k] = nil
    end
  end
end

local specs = {}
local selected = os.getenv("TEST_SPECS")
if selected and selected ~= "" then
  for path in selected:gmatch("%S+") do
    table.insert(specs, path)
  end
else
  local p = assert(io.popen("ls tests/*_spec.lua 2>/dev/null"))
  for line in p:lines() do
    table.insert(specs, line)
  end
  p:close()
  table.sort(specs)
end

if #specs == 0 then
  io.stderr:write("no specs found under tests/\n")
  os.exit(2)
end

for _, spec in ipairs(specs) do
  reset_module_cache()
  _G.hl = require("tests.hl_stub").new()
  _G.config = nil

  t.describe(spec_name(spec), function()
    local ok, err = pcall(dofile, spec)
    if not ok then
      t.it("(failed to load)", function()
        error(err, 0)
      end)
    end
  end)
end

_G.hl = nil

print("")
local code = t.report()
os.exit(code)
