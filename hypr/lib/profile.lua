-- Geometry profile, picked from the outputs rather than the hostname.
--
-- The host files (conf/hosts/) say which workspaces exist per machine — that
-- really is a property of the hostname, since it encodes the workstations we
-- built by hand. Gaps, region rules and layout choices are not: they depend
-- on what the panel actually is, and a hostname has no way to say "this is a
-- 5120x1440 ultrawide". So they're fingerprinted off hl.get_monitors()
-- instead, independent of hostname, and conf/host.lua looks the result up
-- in a `geometry_profiles` table (conf/base.lua) rather than in `config.host`.
--
-- Forcing a profile (to test one machine's geometry from the other) is a
-- deliberate escape hatch, not a keybind: it stayed silent for two weeks once
-- (a manual override outranking the live fingerprint on every load, with no
-- expiry and no announcement) before anyone noticed the desk was wrong. So a
-- force now always carries an expiry, and every load with one standing both
-- notifies and logs loudly (`M.announce`) -- see docs/hyprfocus.md.
local Store = require("hypr.lib.store")

local M = {}

M.DESK_DUAL = "desk-dual"
M.LAPTOP_SOLO = "laptop-solo"

-- A forced profile with no explicit duration defaults to this many minutes --
-- long enough to test a scenario, short enough that forgetting about it does
-- not cost more than a session.
M.DEFAULT_FORCE_MINUTES = 120

-- Below this, a panel reads as a normal-aspect monitor rather than the
-- 5120x1440 ultrawide the desk-dual geometry (region rules, wide side gaps)
-- was built for.
M.ULTRAWIDE_MIN_WIDTH = 3440

---Which geometry an output set wants.
---
---The presence of an ultrawide decides it, not how many outputs there are. A
---5120px panel with its second monitor unplugged still has 5120px of geometry
---to spend, and giving it the laptop's 4/8 gaps would waste exactly the space
---the desk-dual profile exists to use. Counting outputs answered a question
---nobody asked.
---@param monitors HL.Monitor[] as returned by hl.get_monitors()
---@return "desk-dual"|"laptop-solo"
function M.fingerprint(monitors)
  for _, m in ipairs(monitors) do
    if (m.width or 0) >= M.ULTRAWIDE_MIN_WIDTH then
      return M.DESK_DUAL
    end
  end
  return M.LAPTOP_SOLO
end

local store = Store.define("hypr/monitor-profile")

---Live fingerprint of the running compositor's outputs.
---@return "desk-dual"|"laptop-solo"
function M.current()
  return M.fingerprint(hl.get_monitors() or {})
end

---@param iso string? an ISO-8601 UTC timestamp ("...Z"), or nil
---@param now_iso string an ISO-8601 UTC timestamp to compare against
---@return boolean expired true when `iso` is missing or not in the future
local function past(iso, now_iso)
  return type(iso) ~= "string" or iso <= now_iso
end

---A force with no `forced_until` is unverifiable and treated as already
---expired (self-healing the pre-expiry stores this replaces) rather than
---trusted to hold forever. Clears any expired record so the next call reads
---clean and does not re-announce it.
---@return string? name, string? until_iso -- the still-active override, if any
local function live_override()
  local forced, until_iso = store:get("forced"), store:get("forced_until")
  if not forced then
    return nil, nil
  end
  local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
  if past(until_iso, now) then
    store:update(function(t)
      t.forced, t.forced_until = nil, nil
      return t
    end)
    return nil, nil
  end
  return forced, until_iso
end

---The profile this load should apply: a live (unexpired) `M.force()` if one
---is standing, else the live fingerprint.
---@return "desk-dual"|"laptop-solo"
function M.resolve()
  local forced = live_override()
  return forced or M.current()
end

---Writes the resolved profile where Quickshell can read it (e.g. to collapse
---which-key to a bottom sheet on laptop-solo). Called once per config load,
---after conf/host.lua has resolved the profile.
---@param name string
function M.publish(name)
  store:set({ profile = name })
end

---Notify and log loudly, every load, for as long as a force stands -- a
---stale override must be obvious within seconds, not months. Call once per
---config load, after `resolve`/`publish` (conf/host.lua).
function M.announce()
  local forced, until_iso = live_override()
  if not forced then
    return
  end
  pcall(function()
    require("hypr.lib.notify"):notify(
      ("hyprfocus: geometry profile forced to %s until %s -- ,profile-force clear to stop"):format(forced, until_iso),
      0,
      "WARNING"
    )
  end)
  require("hypr.lib.trace").emit({
    stage = "profile",
    event = "forced_active",
    decision = forced,
    reason = "until " .. tostring(until_iso),
  })
end

---Force a named profile, expiring on its own after `minutes` (default
---`M.DEFAULT_FORCE_MINUTES`) so a forgotten override cannot outlive the
---session that needed it. Deliberately not a single keybind (docs/hyprfocus.md
---"Forcing a profile") -- reached only through `,profile-force <name>
---[minutes]`, which requires typing the exact profile name.
---@param name string M.DESK_DUAL or M.LAPTOP_SOLO
---@param minutes number?
---@return boolean ok, string? error
function M.force(name, minutes)
  if name ~= M.DESK_DUAL and name ~= M.LAPTOP_SOLO then
    return false, ("unknown profile %q (want %q or %q)"):format(name, M.DESK_DUAL, M.LAPTOP_SOLO)
  end
  local span = (type(minutes) == "number" and minutes > 0) and minutes or M.DEFAULT_FORCE_MINUTES
  local until_iso = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() + math.floor(span * 60))
  store:set({ forced = name, forced_until = until_iso })
  os.execute("hyprctl reload >/dev/null 2>&1 &")
  return true, nil
end

---Clear a standing force early. `resolve()` returns to the live fingerprint
---on the next load.
function M.clear()
  store:update(function(t)
    t.forced, t.forced_until = nil, nil
    return t
  end)
  os.execute("hyprctl reload >/dev/null 2>&1 &")
end

return M
