-- Instrumented `hl.on` registration.
--
-- The compositor runs every event handler on its own thread and gives each
-- one a budget; a handler that overruns or raises is skipped, and what
-- reaches the journal is the plugin's own one-liner — a file and a line
-- number, with no event name, no window, and no indication that the handler
-- was slow rather than wrong. That is enough to find a nil call and not much
-- else, and a handler that is merely near its budget leaves no trace at all
-- until the day it crosses it.
--
-- So handlers registered through here carry their own record: an error is
-- traced with the event that produced it, and a handler that runs long
-- enough to be worth knowing about says so before it becomes a failure.
--
-- The clock is `os.clock`, which is CPU time, not wall time: it sees a
-- handler that computes too much and does NOT see one blocked on IO. That
-- suits what runs here — the expensive handlers in this config walk the live
-- window list, and the one thing they must never do is block (trace and
-- every exec are fire-and-forget for exactly that reason), so CPU time is
-- the honest measure of a handler's own cost.
local trace = require("hypr.lib.trace")

local M = {}

-- Long enough that ordinary handlers never report, short enough to land well
-- inside the compositor's own budget — the point is a warning before a skip,
-- not after one.
M.SLOW_SECONDS = 0.05

---Register `fn` for `event`, recording what it costs and what it raises.
---@param event string the `hl.on` event name
---@param fn fun(...) the handler
---@param name string? what to call it in the record; defaults to the event
---@return boolean registered false when `hl.on` is unavailable (the stub)
function M.on(event, fn, name)
  if type(hl) ~= "table" or type(hl.on) ~= "function" then
    return false
  end
  local label = name or event
  hl.on(event, function(...)
    local started = os.clock()
    local args = table.pack(...)
    local ok, err = pcall(function()
      return fn(table.unpack(args, 1, args.n))
    end)
    local elapsed = os.clock() - started
    if not ok then
      trace.emit({
        stage = "interact",
        event = "handler_failed",
        decision = "skip",
        reason = ("%s raised: %s"):format(label, tostring(err)),
        seconds = ("%.4f"):format(elapsed),
      })
      return
    end
    if elapsed >= M.SLOW_SECONDS then
      trace.emit({
        stage = "interact",
        event = "handler_slow",
        decision = "admit",
        reason = ("%s took %.0f ms of CPU"):format(label, elapsed * 1000),
        seconds = ("%.4f"):format(elapsed),
      })
    end
  end)
  return true
end

return M
