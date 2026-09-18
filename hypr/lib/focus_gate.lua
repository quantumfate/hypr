-- Focus mode oracles, compositor side.
--
-- Bind handlers used to answer "may I launch this" by spawning
-- `qs ipc call focus canLaunch …` — a subprocess per press, on the
-- compositor thread, failing in interesting ways while the shell restarts.
-- The store IS the source of truth and it is readable from here without a
-- question: `mood-policy.json` carries the launch policy and scene
-- reachability per mode, `focus.json` is the pointer, and the store handles
-- are mtime-cached, so a dispatch-time check costs one already-cached read.
--
-- The verdicts must match Focus.qml's (`canLaunch`/`sceneState`): this is
-- the second language the mood semantics are expressed in, and the pin is
-- cross-repo — the quickshell tests pin the policy table and this module
-- carries its mirror. A drift here is a test failure on one side or the
-- other, not a silent difference (the policy asset is shared data).
-- LEO-287 tracks the pair.
--
-- Mode semantics (mirroring Focus.qml, LEO-236):
--   * `neutral` never blocks anything — it is the hidden recovery mode, never
--     a boot default; `work` IS the boot/resting mode but is an ordinary mood
--     otherwise, so a `mood-policy` entry for it may block (media/games
--     blocked from login is accepted behaviour);
--   * a mood never blocks launching into its own kind (`kindOwner` links the
--     launch vocabulary to the mood ids after the trim);
--   * `until` expiry lapses the block on its own — a stale mood stops
--     blocking rather than waiting for something to clear it;
--   * `soft` aggression warns and lets through; `firm`/`hard` refuse;
--   * scene reachability: absent means reachable, so only what a mood takes
--     away names itself (absent-from-policy = open door the same way).
local store = require("hypr.lib.store")

local M = {}

--- The launch kind a mood id owns — same table, same reason.
local KIND_OWNER = { game = "gaming" }

---@param until_at string? ISO-8601 UTC (`Z`) expiry
---@return boolean expired? tolerant of malformed input (treated as live)
local function past(until_at)
  if type(until_at) ~= "string" then
    return false
  end
  -- os.time parses ISO via epoch math; a malformed expiry is treated as
  -- still live, because an expired-with-future-stamp fallback is safer than
  -- a stale block. Lua has no ISO parser in the standard library; the
  -- quickshell side owns formatting, so this comparator stays tolerant.
  --
  -- `os.time(t)` reads `t`'s fields as LOCAL time, but `until_at`'s fields
  -- are UTC, so the raw parse is off by the host's UTC offset. `gap` is that
  -- offset (round-tripping "now" through both calendars), added back to the
  -- parsed stamp before comparing.
  --
  -- `os.date("!*t", now)` stamps `isdst = false` (UTC has no DST); clearing
  -- it before the round-trip lets `os.time` resolve DST for the date itself
  -- instead of trusting a false flag, which shorted `gap` by an hour during
  -- DST (see `hypr/hyprfocus/init.lua`'s `expired`, the same bug).
  local y, mo, d, h, mi = until_at:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
  if not y then
    return false
  end
  local now = os.time()
  local utc_now = os.date("!*t", now)
  utc_now.isdst = nil
  local gap = now - os.time(utc_now)
  return os.time({
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
  }) + gap < now
end

---@param pointer table pointer document ({ mode, until, previous, ... })
---@return string? reason nil unless the effective mode is an active, non-neutral mood
local function active_reason(pointer)
  if type(pointer) ~= "table" then
    return nil
  end
  -- Effective mode: the pointer's own, unless a timed mode expired, in which
  -- case `previous` (the mode it was layered over) applies, falling back to
  -- `work` — which, unlike `neutral`, is a real mood and may carry its own
  -- policy (work blocking media/games from login is accepted behaviour).
  local mode = pointer.mode
  if past(pointer["until"]) then
    mode = pointer.previous or "work"
  end
  if not mode or mode == "neutral" then
    return nil
  end
  return mode
end

---The launch-kind gate. Returns nil when the launch may proceed.
---@param kind string "media"|"game"
---@return string? reason non-nil when the active mood blocks this kind
function M.block_reason(kind)
  local policy = store.define("mood-policy"):get("moods")
  local pointer = store.define("focus"):get()
  local mode = active_reason(pointer)
  if not mode or type(policy) ~= "table" then
    return nil
  end
  local mood = policy[mode]
  if type(mood) ~= "table" then
    return nil
  end
  -- The mood itself does not refuse what it exists for.
  if mode == kind or KIND_OWNER[kind] == mode then
    return nil
  end
  local launches = type(mood.launches) == "table" and mood.launches or {}
  local block = type(launches.block) == "table" and launches.block or {}
  for _, blocked in ipairs(block) do
    if blocked == kind and launches.aggression ~= "soft" then
      return (mood.name or mode) .. " is on — this is blocked while it runs"
    end
  end
  return nil
end

---Scene reachability under the pointer's mood. Absent means reachable.
---@param scene string the scene's workspace default_name
---@return string? reason non-nil when the mood blocks the scene
function M.blocked_scene(scene)
  local policy = store.define("mood-policy"):get("moods")
  local pointer = store.define("focus"):get()
  local mode = active_reason(pointer)
  if not mode or type(policy) ~= "table" then
    return nil
  end
  local mood = policy[mode]
  if type(mood) ~= "table" or type(mood.scenes) ~= "table" then
    return nil
  end
  if mood.scenes[scene] == "blocked" then
    return "the " .. scene .. " scene is blocked while this mood runs"
  end
  return nil
end

return M
