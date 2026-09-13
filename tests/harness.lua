--- A test harness small enough to not need explaining.
---
--- Plain Lua, not busted: hypr/lib/* is pure Lua with no compositor dependency,
--- so a real interpreter (no Hyprland, no mocks framework) is enough to run it.
---@class tests.harness
local M = {}

---@class tests.Result
---@field name string
---@field ok boolean
---@field err string?

---@type tests.Result[]
M.results = {}

--- Current describe() label, prefixed onto each test name.
local group = ""

---@param name string
---@param fn fun()
function M.describe(name, fn)
  local previous = group
  group = previous == "" and name or (previous .. " › " .. name)
  fn()
  group = previous
end

---@param name string
---@param fn fun()
function M.it(name, fn)
  local label = group == "" and name or (group .. " › " .. name)
  local ok, err = xpcall(fn, function(e)
    return debug.traceback(tostring(e), 2)
  end)
  table.insert(M.results, { name = label, ok = ok, err = not ok and err or nil })
end

---@param value any
---@param message? string
function M.ok(value, message)
  if not value then
    error(message or ("expected truthy, got " .. tostring(value)), 2)
  end
end

---@param a any
---@param b any
---@return boolean
local function deep_equal(a, b)
  if a == b then
    return true
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  for k, v in pairs(a) do
    if not deep_equal(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

---@param v any
---@return string
local function inspect(v)
  if type(v) ~= "table" then
    return tostring(v)
  end
  local parts = {}
  for k, val in pairs(v) do
    parts[#parts + 1] = tostring(k) .. "=" .. inspect(val)
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

---@param expected any
---@param actual any
---@param message? string
function M.eq(expected, actual, message)
  if not deep_equal(expected, actual) then
    error(
      ("%s\n  expected: %s\n  actual:   %s"):format(message or "values differ", inspect(expected), inspect(actual)),
      2
    )
  end
end

--- A fresh temp directory, cleaned up by the OS (not us) — tests only need it
--- to exist for the run, and there is no cross-run state to protect.
---@return string path
function M.tempdir()
  local dir = os.tmpname()
  os.remove(dir)
  os.execute(("mkdir -p %q"):format(dir))
  return dir
end

--- Prints the report and returns the exit code.
---@return integer
function M.report()
  local failed = {}
  for _, result in ipairs(M.results) do
    if not result.ok then
      table.insert(failed, result)
    end
  end

  for _, result in ipairs(M.results) do
    print((result.ok and "  ok   " or "  FAIL ") .. result.name)
  end
  print("")
  print(("%d passed, %d failed, %d total"):format(#M.results - #failed, #failed, #M.results))

  for _, result in ipairs(failed) do
    print("")
    print("FAIL " .. result.name)
    print(result.err)
  end

  return #failed == 0 and 0 or 1
end

return M
