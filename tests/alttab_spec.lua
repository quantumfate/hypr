-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- LEO-375: ALT+TAB crashed with "attempt to compare number with nil" because
--- the sort comparator and the special-workspace filter both read fields that
--- are nil on held/special windows. These specs build exactly that shape.
local t = require("tests.harness")

---@param address string
---@param focus_history_id number?
---@param workspace table
---@return table
local function win(address, focus_history_id, workspace)
  return {
    address = address,
    title = address,
    class = "kitty",
    focus_history_id = focus_history_id,
    workspace = workspace,
  }
end

---Fresh module: alttab.lua is side-effecting only (`init.lua` requires it for
---its `hl.bind` calls, not a return value), so the way to drive it is the
---same as a real ALT+TAB press — through the bind it registered.
---@param windows table[]
---@param active table?
---@return fun() press_alt_tab, string alttab_dir
local function fresh(windows, active)
  for k in pairs(package.loaded) do
    if k == "hypr" or k:match("^hypr%.") then
      package.loaded[k] = nil
    end
  end
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  stub.get_windows = function()
    return windows
  end
  stub.get_active_window = function()
    return active
  end
  _G.config = nil

  require("hypr.services.alttab.alttab")

  local action
  for _, b in ipairs(stub.binds) do
    if b.key == "ALT + TAB" then
      action = b.action
    end
  end
  assert(action, "expected ALT + TAB to be bound")
  return action, os.getenv("XDG_RUNTIME_DIR") .. "/hypr/alttab"
end

---@param dir string
---@return string[] addresses left in the picker's input, in order
local function picked(dir)
  local f = assert(io.open(dir .. "/input", "r"))
  local body = f:read("*a")
  f:close()
  local out = {}
  for line in body:gmatch("[^\n]+") do
    out[#out + 1] = line:match("^([^\t]+)")
  end
  return out
end

t.describe("alttab", function()
  t.it("does not crash sorting a window with no focus history (held/never-focused)", function()
    local windows = {
      win("0x1", 3, { id = 1, name = "code", monitor = { name = "DP-1" } }),
      -- Held windows carry no focus history in this shape; a bare `<` on it
      -- is exactly the "compare number with nil" crash.
      win("0x2", nil, { name = "special:hyprfocus-held" }),
      win("0x3", 1, { id = 1, name = "code", monitor = { name = "DP-1" } }),
    }
    local press, dir = fresh(windows)

    local ok = pcall(function()
      press()
    end)
    t.ok(ok, "ALT+TAB crashed on a nil focus_history_id")

    t.eq({ "0x3", "0x1" }, picked(dir))
  end)

  t.it("excludes special workspaces even when workspace.id is nil", function()
    local windows = {
      win("0x1", 1, { id = 1, name = "code", monitor = { name = "DP-1" } }),
      -- A renamed/retired workspace resolves with no id at all; the old
      -- `w.workspace.id >= 0` check crashed on this instead of excluding it.
      win("0x2", 2, { name = "special:shelf-music" }),
    }
    local press, dir = fresh(windows)

    press()

    t.eq({ "0x1" }, picked(dir))
  end)

  t.it("excludes windows on a host-ignored monitor", function()
    local windows = {
      win("0x1", 1, { id = 1, name = "code", monitor = { name = "DP-1" } }),
      win("0x2", 2, { id = 2, name = "media", monitor = { name = "HDMI-A-1" } }),
    }
    local press, dir = fresh(windows)
    -- fresh() resets `_G.config`, so a host fixture is set after it.
    _G.config = { host = { ignored_monitors = { "HDMI-A-1" } } }

    press()

    t.eq({ "0x1" }, picked(dir))
  end)

  t.it("treats a nil host.ignored_monitors as no exclusions", function()
    local windows = {
      win("0x1", 1, { id = 1, name = "code", monitor = { name = "DP-1" } }),
    }
    local press, dir = fresh(windows)
    _G.config = { host = {} }

    press()

    t.eq({ "0x1" }, picked(dir))
  end)
end)
