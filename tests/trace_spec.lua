-- hypr/lib/trace.lua: the lifecycle log sink (LEO-352).
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")

local function fresh()
  local stub = require("tests.hl_stub").new()
  _G.hl = stub
  package.loaded["hypr.lib.trace"] = nil
  return stub, require("hypr.lib.trace")
end

---The exec_cmd commands dispatched (via `hl.dsp.exec_cmd` + `hl.dispatch`,
---the fire-and-forget spawn `emit` uses), in call order.
---@param stub table
---@return string[]
local function exec_cmds(stub)
  local out = {}
  for _, action in ipairs(stub.dispatched) do
    if action.name == "dsp.exec_cmd" then
      out[#out + 1] = action.args[1]
    end
  end
  return out
end

---Decode the base64 payload `emit` piped into `logger --journald`, so specs
---assert on the journal entry it built rather than on shell-quoting details.
---@param cmd string
---@return string
local function decoded_payload(cmd)
  local b64 = cmd:match("echo (%S+) | base64 %-d")
  t.ok(b64, "exec_cmd carries a base64 payload: " .. cmd)
  local handle = assert(io.popen(("echo '%s' | base64 -d"):format(b64)))
  local out = handle:read("*a")
  handle:close()
  return out
end

t.describe("trace.emit", function()
  t.it("does nothing for a record with no stage/event", function()
    local stub, trace = fresh()
    trace.emit({ decision = "route" })
    t.eq(0, #exec_cmds(stub))
  end)

  t.it("does nothing without a compositor to dispatch to", function()
    _G.hl = nil
    package.loaded["hypr.lib.trace"] = nil
    local trace = require("hypr.lib.trace")
    -- No error is the assertion: a pure decision path must survive this.
    trace.emit({ stage = "identify", event = "matched" })
  end)

  t.it("writes one journal entry via logger --journald, non-blocking", function()
    local stub, trace = fresh()
    trace.emit({
      stage = "identify",
      event = "matched",
      decision = "route",
      reason = "matched scene gaming",
      trace = "0x1",
      class = "Dofus.x64",
    })
    local cmds = exec_cmds(stub)
    t.eq(1, #cmds)
    local cmd = cmds[1]
    t.ok(cmd:match("logger %-%-journald"), cmd)

    local payload = decoded_payload(cmd)
    t.ok(payload:match("SYSLOG_IDENTIFIER=hyprfocus"), payload)
    t.ok(payload:match("TRACE=0x1"), payload)
    t.ok(payload:match("CLASS=Dofus%.x64"), payload)
    t.ok(payload:match("MESSAGE=identify%.matched route matched scene gaming"), payload)
  end)

  t.it("uppercases every record field as its own journal field", function()
    local stub, trace = fresh()
    trace.emit({ stage = "leave", event = "closed", decision = "leave", workspace = "gaming" })
    local payload = decoded_payload(exec_cmds(stub)[1])
    t.ok(payload:match("STAGE=leave"), payload)
    t.ok(payload:match("EVENT=closed"), payload)
    t.ok(payload:match("WORKSPACE=gaming"), payload)
  end)
end)
