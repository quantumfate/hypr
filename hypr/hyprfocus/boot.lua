-- Pure boot decision: what mode login should land the desk in, and whether
-- the pointer must be rewritten to say so.
--
-- Product decision (not a reinterpretation of the general expiry rule
-- `hyprfocus/init.lua`'s `effective_mode` applies everywhere else): login
-- always enters `work`, UNLESS the pointer names a timed mode that is still
-- running (`until` in the future), in which case that mode resumes as
-- itself and keeps its own `previous`. This deliberately overrides the
-- fallback-to-`previous` rule for an EXPIRED timed pointer at boot — a stale
-- timed mode boots to `work` directly, never to whatever it was layered
-- over. `neutral` is therefore never a boot destination: it is reached only
-- through the recovery bind (docs/desktop-model.md "Focus mode").
--
-- Pure: no `hl`, no store, no IO, no clock of its own (`expired` and `now`
-- are handed in). `hypr/hyprfocus/init.lua`'s `M.boot` is the thin executor
-- that reads the pointer, calls this, and applies the answer.
local M = {}

---Whether the pointer names a mode that is both declared and still running
---as a timed mode right now.
---@param pointer table? the pointer document, as read from the store (nil if missing)
---@param known_modes table<string, table> declaration.modes, keyed by mode name
---@param expired fun(until_at: string?): boolean the same expiry test `init.lua` uses
---@return boolean
local function resumable(pointer, known_modes, expired)
  if not pointer then
    return false
  end
  local mode = pointer.mode
  if not mode or not known_modes[mode] then
    return false
  end
  return type(pointer["until"]) == "string" and not expired(pointer["until"])
end

---@alias Hyprfocus.BootAction "resume"|"enter_work"

---Decide login's mode. Covers, by construction:
---  - a missing store (`pointer == nil`) -> `enter_work`
---  - a stale/expired timed pointer -> `enter_work` (never its `previous`)
---  - an unexpired timed pointer for a declared mode -> `resume`
---  - a pointer naming an unknown mode (timed or not) -> `enter_work`
---@param pointer table? the pointer document, as read from the store
---@param known_modes table<string, table> declaration.modes, keyed by mode name
---@param expired fun(until_at: string?): boolean
---@return Hyprfocus.BootAction action
---@return string mode the mode to converge on: the pointer's, or "work"
function M.decide(pointer, known_modes, expired)
  if resumable(pointer, known_modes, expired) then
    return "resume", pointer.mode
  end
  return "enter_work", "work"
end

return M
