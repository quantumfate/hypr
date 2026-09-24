-- hypr/lib/handlers.lua: instrumented `hl.on` registration. The handler still
-- runs; what it costs and what it raises becomes a record.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")

---@return table handlers, table records, table registered
local function fresh()
  local records = {}
  package.loaded["hypr.lib.trace"] = {
    emit = function(r)
      records[#records + 1] = r
    end,
  }
  local registered = {}
  _G.hl = {
    on = function(event, fn)
      registered[event] = fn
    end,
  }
  package.loaded["hypr.lib.handlers"] = nil
  return require("hypr.lib.handlers"), records, registered
end

---@param records table[]
---@param event string
---@return table?
local function record_for(records, event)
  for _, r in ipairs(records) do
    if r.event == event then
      return r
    end
  end
  return nil
end

t.describe("handlers.on", function()
  t.it("runs the handler, with its arguments", function()
    local handlers, _, registered = fresh()
    local seen
    handlers.on("window.open", function(w)
      seen = w
    end)
    registered["window.open"]({ address = "0x1" })
    t.eq("0x1", seen.address)
  end)

  t.it("records what an event a handler raised on was", function()
    local handlers, records, registered = fresh()
    handlers.on("window.close", function()
      error("boom", 0)
    end)
    registered["window.close"]({})
    local failed = record_for(records, "handler_failed")
    t.eq("skip", failed.decision)
    t.eq(true, failed.reason:find("window.close", 1, true) ~= nil)
    t.eq(true, failed.reason:find("boom", 1, true) ~= nil)
  end)

  t.it("does not let a raising handler take the compositor's event down", function()
    local handlers, _, registered = fresh()
    handlers.on("window.active", function()
      error("boom", 0)
    end)
    -- The registered function is what the compositor calls: it must return
    -- normally even when the handler inside it did not.
    local ok = pcall(registered["window.active"], {})
    t.eq(true, ok)
  end)

  t.it("says nothing about a handler that is quick", function()
    local handlers, records, registered = fresh()
    handlers.on("workspace.active", function() end)
    registered["workspace.active"]()
    t.eq(nil, record_for(records, "handler_slow"))
    t.eq(nil, record_for(records, "handler_failed"))
  end)

  t.it("names the handler when one is given, rather than the raw event", function()
    local handlers, records, registered = fresh()
    handlers.on("window.open", function()
      error("boom", 0)
    end, "stray float")
    registered["window.open"]({})
    t.eq(true, record_for(records, "handler_failed").reason:find("stray float", 1, true) ~= nil)
  end)

  t.it("registers nothing, and says so, without a compositor", function()
    local handlers = fresh()
    _G.hl = {}
    t.eq(false, handlers.on("window.open", function() end))
  end)
end)

return t
