-- Resolver conformance (LEO-287).
--
-- The resolver exists twice by deliberate choice (compositor-update path
-- and no-compositor CLI), and the danger is the two implementations saying
-- different things about what a mode means. This spec runs the SAME fixture
-- set the Python side's `conform` verb runs — hypr/tests/fixtures/hyprfocus/
-- resolver/*.json — so a divergence appears as a fixture failure here before
-- it appears as a desk that disagrees with itself.
--
-- Error wording is allowed to drift between the implementations; the desks
-- may not. Error fixtures therefore match on substring, never on the whole
-- message.
local t = require("tests.harness")
local json = require("hypr.lib.json")
local resolve_module = require("hypr.hyprfocus.resolve")

local fixtures_dir = (debug.getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/fixtures/hyprfocus/resolver")

---@param a any
---@param b any
---@return boolean
local function deep_equal(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= "table" then
    return a == b
  end
  local keys = {}
  for k in pairs(a) do
    keys[k] = true
  end
  for k in pairs(b) do
    keys[k] = true
    if not keys[k] then
      return false
    end
  end
  for k in pairs(a) do
    if not deep_equal(a[k], b[k]) then
      return false
    end
  end
  return true
end

-- List ordering is part of the desk: apply_base preserves the declaration's
-- order, and closure appends after it. A fixture's `expected` list encodes
-- this, and the compare treats `["a", "b"] ~= ["b", "a"]`.
local function fixture_files()
  local out = {}
  local pipe = io.popen(('find "%s" -maxdepth 1 -name "*.json" | sort'):format(fixtures_dir))
  for line in pipe:lines() do
    out[#out + 1] = line
  end
  pipe:close()
  return out
end

t.describe("resolver conformance fixtures (LEO-287)", function()
  t.it("runs every shared fixture through the Lua resolver", function()
    local files = fixture_files()
    t.ok(#files > 0, "no conformance fixtures found — the gate runs on no data")
    for _, path in ipairs(files) do
      local fixture = json.decode(assert(io.open(path, "r"):read("*a")))
      local want_error = fixture.expected_error
      local ok, desk_or_err = pcall(resolve_module.resolve, fixture.declaration, fixture.mode)
      if want_error then
        t.ok(not ok, ("%s: resolved, but the fixture expected an error"):format(fixture.name or path))
        if not ok then
          t.ok(
            tostring(desk_or_err):find(want_error, 1, true),
            ("%s: message does not carry the fixture's substring (have %q)"):format(fixture.name, tostring(desk_or_err))
          )
        end
      else
        t.ok(
          ok,
          ("%s: the resolver refused a fixture expecting a desk: %s"):format(fixture.name, tostring(desk_or_err))
        )
        if ok then
          t.ok(deep_equal(desk_or_err, fixture.expected), ("%s: desk disagrees with the fixture"):format(fixture.name))
        end
      end
    end
  end)
end)
