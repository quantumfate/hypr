-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
--- A launch toggle announces once. The reset used to fire its own toast, so a
--- single `SUPER+d` then `d` produced two notifications.
local t = require("tests.harness")
local launch = require("hypr.services.dofus.launch")

---Toasts go through `hypr.lib.notify`, which issues one `notify toast` exec per
---call — so counting those execs counts the announcements.
---@return integer
local function toast_count()
  local n = 0
  for _, cmd in ipairs(hl.exec_cmds) do
    if cmd:find("notify toast", 1, true) then
      n = n + 1
    end
  end
  return n
end

t.describe("dofus.launch", function()
  t.it("toggling on announces exactly once", function()
    hl.exec_cmds = {}
    launch.enabled = false
    launch:toggle_enable()
    t.eq(1, toast_count())
    t.ok(hl.exec_cmds[1]:find("Dofus Launch Enabled", 1, true))
  end)

  t.it("toggling off announces exactly once", function()
    hl.exec_cmds = {}
    launch:toggle_enable()
    t.eq(1, toast_count())
    t.ok(hl.exec_cmds[1]:find("Dofus Launch Disabled", 1, true))
  end)

  t.it("reset_counter is silent, so its callers own the one announcement", function()
    hl.exec_cmds = {}
    launch:reset_counter()
    t.eq(0, toast_count())
    t.eq(1, launch.counter)
  end)
end)
