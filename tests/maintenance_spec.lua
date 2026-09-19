-- hypr/lib/maintenance.lua: automatic seed/reseed at session start.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")

---Fresh maintenance module over a scratch store dir, with `os.execute` and
---`hypr.lib.trace` both recorded instead of actually shelling out or logging.
---`shipped_version` nil means "no sibling checkout" (shipped_declaration_path
---resolves to a file that does not exist).
---@param shipped_version integer?
---@param stored table? what the hyprfocus store already holds
---@return table maintenance, table exec_calls, table trace_events, fun() restore
local function fresh(shipped_version, stored)
  local dir = t.tempdir()
  local real_getenv = os.getenv
  os.getenv = function(k)
    if k == "QF_STORE" then
      return dir
    end
    if k == "XDG_STATE_HOME" then
      return dir .. "/legacy"
    end
    return real_getenv(k)
  end

  package.loaded["hypr.lib.store"] = nil
  local Store = require("hypr.lib.store")
  if stored then
    Store.define("hyprfocus"):put(stored)
  end
  -- Out of scope for these specs: pre-populate so maintain_projects() is a
  -- no-op and every exec_calls count below is hyprfocus_seed's alone.
  Store.define("projects"):put({ projects = {} })

  local shipped_path = dir .. "/shipped.json"
  if shipped_version then
    local f = assert(io.open(shipped_path, "w"))
    f:write(('{"version": %d}'):format(shipped_version))
    f:close()
  end

  local exec_calls = {}
  local real_execute = os.execute
  os.execute = function(cmd)
    exec_calls[#exec_calls + 1] = cmd
    return true
  end

  local trace_events = {}
  package.loaded["hypr.lib.trace"] = {
    emit = function(r)
      trace_events[#trace_events + 1] = r
    end,
  }
  package.loaded["hypr.lib.maintenance"] = nil
  local maintenance = require("hypr.lib.maintenance")
  maintenance.shipped_declaration_path = function()
    return shipped_path
  end

  return maintenance,
    exec_calls,
    trace_events,
    function()
      os.getenv = real_getenv
      os.execute = real_execute
      package.loaded["hypr.lib.trace"] = nil
    end
end

t.describe("maintenance.run()", function()
  t.it("seeds a missing declaration and logs one maintenance event", function()
    local maintenance, exec_calls, trace_events, restore = fresh(7, nil)
    maintenance.run()
    t.eq(1, #exec_calls, "exactly one seed invocation")
    t.ok(exec_calls[1]:match("hyprfocus seed"), exec_calls[1])
    t.eq(1, #trace_events)
    t.eq("maintenance", trace_events[1].stage)
    t.eq("hyprfocus_seed", trace_events[1].event)
    t.eq("seeded", trace_events[1].decision)
    t.eq("missing", trace_events[1].reason)
    restore()
  end)

  t.it("reseeds a stale declaration and says why", function()
    local maintenance, exec_calls, trace_events, restore = fresh(7, { version = 3 })
    maintenance.run()
    t.eq(1, #exec_calls)
    t.eq("stale v3", trace_events[1].reason)
    restore()
  end)

  t.it("does nothing when the declaration is already at the shipped version", function()
    local maintenance, exec_calls, trace_events, restore = fresh(7, { version = 7 })
    maintenance.run()
    t.eq(0, #exec_calls, "no subprocess when nothing is missing or stale")
    t.eq(0, #trace_events)
    restore()
  end)

  t.it("a store ahead of the shipped version is left alone", function()
    local maintenance, exec_calls, _, restore = fresh(7, { version = 8 })
    maintenance.run()
    t.eq(0, #exec_calls)
    restore()
  end)

  t.it("no sibling checkout to seed from: silent no-op, not an error", function()
    local maintenance, exec_calls, trace_events, restore = fresh(nil, nil)
    maintenance.run()
    t.eq(0, #exec_calls)
    t.eq(0, #trace_events)
    restore()
  end)
end)
