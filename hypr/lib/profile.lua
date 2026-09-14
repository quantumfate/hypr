-- Geometry profile, picked from the outputs rather than the hostname.
--
-- The host files (conf/hosts/) say which workspaces exist per machine — that
-- really is a property of the hostname, since it encodes the workstations we
-- built by hand. Gaps, region rules and layout choices are not: they depend
-- on what the panel actually is, and a hostname has no way to say "this is a
-- 5120x1440 ultrawide". So they're fingerprinted off hl.get_monitors()
-- instead, independent of hostname, and conf/host.lua looks the result up
-- in a `geometry_profiles` table (conf/base.lua) rather than in `config.host`.
local Store = require("hypr.lib.store")

local M = {}

M.DESK_DUAL = "desk-dual"
M.LAPTOP_SOLO = "laptop-solo"

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

---The profile this load should apply: a manual override from
---M.switch() if one is standing, else the live fingerprint.
---@return "desk-dual"|"laptop-solo"
function M.resolve()
  return store:get("forced") or M.current()
end

---Writes the resolved profile where Quickshell can read it (e.g. to collapse
---which-key to a bottom sheet on laptop-solo). Called once per config load,
---after conf/host.lua has resolved the profile.
---@param name string
function M.publish(name)
  store:set({ profile = name })
end

---Manual toggle for SUPER Space w m (bound in hypr/binds.lua, which we don't
---own — see the report for the exact bind). Flips the override and reloads,
---so the flip actually takes effect: geometry is only resolved at config
---load, not on the fly.
---
---hyprctl dispatch-able: `hl.dispatch` insists on a dispatcher or a function,
---not a bare call result, so wrap it —
---  hyprctl dispatch 'function() require("hypr.lib.profile").switch() end'
---@return string the profile now forced
function M.switch()
  local other = M.resolve() == M.DESK_DUAL and M.LAPTOP_SOLO or M.DESK_DUAL
  store:set({ forced = other })
  os.execute("hyprctl reload >/dev/null 2>&1 &")
  return other
end

return M
