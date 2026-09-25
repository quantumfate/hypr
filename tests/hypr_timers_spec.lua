-- Test fixtures stub the runtime and re-require modules fresh.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
-- `hypr.lib.hypr`'s one-shot timers.
--
-- `hl.timer` keeps no strong reference of its own, so a caller that discards
-- the handle -- `oneshot(25, step)`, the shape of every phase chain and queued
-- move in this repo -- left the timer reachable only from a dead local. Lua
-- collected it whenever it felt like it and the callback never ran: no error,
-- no trace, the chain simply stopped. `oneshot` therefore holds every armed
-- timer itself until it fires.
local t = require("tests.harness")

---@return any stub, any hypr
local function fresh()
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  package.loaded["hypr.lib.hypr"] = nil
  return stub, require("hypr.lib.hypr")
end

t.describe("hypr.oneshot", function()
  t.it("holds an armed timer even when the caller discards the handle", function()
    local stub, hypr = fresh()
    local ran = 0
    hypr.oneshot(25, function()
      ran = ran + 1
    end)

    t.eq(1, hypr.armed_count(), "the timer is reachable from the module, not only from the caller")
    stub.drain()
    t.eq(1, ran, "and it fires")
  end)

  t.it("lets go once it has fired, so the registry is not a leak", function()
    local stub, hypr = fresh()
    hypr.oneshot(25, function() end)
    stub.drain()
    t.eq(0, hypr.armed_count())
  end)

  t.it("still returns the handle, so a caller can cancel or re-arm", function()
    local stub, hypr = fresh()
    local ran = 0
    local handle = hypr.oneshot(25, function()
      ran = ran + 1
    end)
    handle:set_enabled(false)
    stub.drain()
    t.eq(0, ran, "a cancelled one-shot does not fire")
  end)

  t.it("a chain of one-shots runs to its end", function()
    -- The apply's phase chain: each step arms the next and drops the handle.
    local stub, hypr = fresh()
    local steps = {}
    local function step(n)
      steps[#steps + 1] = n
      if n < 4 then
        hypr.oneshot(25, function()
          step(n + 1)
        end)
      end
    end
    hypr.oneshot(900, function()
      step(1)
    end)
    stub.drain()
    t.eq(4, #steps, "every phase is reached")
    t.eq(0, hypr.armed_count())
  end)
end)
