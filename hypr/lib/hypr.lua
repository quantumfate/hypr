local M = {}

-- Thin helpers over the Hyprland runtime API for *flat* reactions — logic that
-- only cares about "what is true right now", not about our submap navigation
-- tree. Contrast hypr/lib/submap.lua, which owns a stack because back/exit are
-- nesting-aware (a parent stays logically entered while you're in its child).
-- Hyprland's `keybinds.submap` event is flat: it reports the active submap, not
-- how you got there. So it is the right tool for things like the passive peek
-- cheatsheet, and the wrong tool for the submap stack.

-- Subscribers notified on every submap transition, with the new submap name
-- ("" at root). Registered via M.on_submap_change.
---@type fun(submap: string)[]
local submap_subs = {}
-- Last submap we saw, to suppress duplicate events and detect real changes.
local last_submap = nil

hl.on("keybinds.submap", function()
  local cur = hl.get_current_submap() -- "" at root/global
  if cur == last_submap then
    return
  end
  last_submap = cur
  for _, cb in ipairs(submap_subs) do
    cb(cur)
  end
end)

---React to submap changes. `cb` gets the new submap name ("" = root). Fires on
---every transition, in registration order.
---@param cb fun(submap: string)
function M.on_submap_change(cb)
  submap_subs[#submap_subs + 1] = cb
end

-- Every armed one-shot, held until it fires.
--
-- `hl.timer` hands back a handle and keeps no strong reference of its own, so
-- a caller that discards it -- `oneshot(25, step)`, the shape of every phase
-- chain and queued move in this repo -- leaves the timer reachable only from
-- a local that is already dead. Lua then collects it whenever it feels like
-- it and the callback simply never runs: no error, no trace, the chain just
-- stops. That is the intermittent half-applied mode swap (live, 2026-09-24):
-- the apply's phase chain stalled between two phases, `transition.finish`
-- was never reached, the bracket force-settled 8s later on its failsafe, and
-- with the settle callback went the landing on the mode's main scene and the
-- companion reconvergence -- which is why a withdrawn scene kept its browser
-- and the desk stayed on whatever workspace it was on.
--
-- Keyed by the handle, cleared when it fires. A cancelled timer
-- (`:set_enabled(false)`) keeps its entry until the process ends; that is a
-- handful of dead table keys per session against a class of silent stalls.
---@type table<any, true>
local armed = {}

---A one-shot timer that runs `cb` after `ms` milliseconds. Returns the handle
---so callers can cancel (`:set_enabled(false)`) or re-arm (`:set_timeout(ms)`).
---The handle is retained here as well, so DISCARDING it is safe.
---@param ms integer
---@param cb fun()
---@return HL.Timer
function M.oneshot(ms, cb)
  local handle
  handle = hl.timer(function()
    armed[handle] = nil
    cb()
  end, { timeout = ms, type = "oneshot" })
  armed[handle] = true
  return handle
end

---How many one-shots are armed right now. For specs and `,hyprfocus log`.
---@return integer
function M.armed_count()
  local n = 0
  for _ in pairs(armed) do
    n = n + 1
  end
  return n
end

return M
