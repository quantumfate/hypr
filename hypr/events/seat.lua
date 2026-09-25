-- Which monitor the keyboard is on, tracked from the compositor's own events.
--
-- Everything that answers this question by asking lies at least some of the
-- time. `hl.get_active_monitor()` and `hl.get_active_workspace()` report the
-- monitor the compositor last MARKED focused, and that mark does not follow a
-- focus that crossed outputs: measured with the keyboard in a window on DP-2,
-- both still answered DP-1 and DP-1's workspace. `hypr/events/layout_opts.lua`
-- names the same trap from the other side -- focusing an empty workspace
-- leaves both pointing at the previous one.
--
-- `monitor.focused` and `workspace.active` do not lie: they fire with the
-- monitor and the workspace the compositor just moved to, in that order, and
-- they fired correctly in exactly the cases the getters got wrong (spiked
-- live, 2026-09-25). So the seat is remembered as it happens rather than
-- reconstructed afterwards.
--
-- Read by `mod+h/l` (`hypr/binds.lua`), which has no window to read a seat
-- off when it is standing on an empty workspace -- `misc.no_focus_fallback`
-- leaves the keyboard on nothing at all there.
local M = {}

---@type string? the monitor the last focus event named
local monitor_name = nil

hl.on("monitor.focused", function(monitor)
  if monitor and monitor.name then
    monitor_name = monitor.name
  end
end)

-- A workspace switch on the same monitor emits no `monitor.focused`, so this
-- only confirms the seat; it is here because a switch onto an EMPTY workspace
-- is the case where the getters go stale, and the event still arrives.
hl.on("workspace.active", function(workspace)
  if workspace and workspace.name then
    local ok, active = pcall(hl.get_monitors)
    if ok then
      for _, m in ipairs(active or {}) do
        local ws = m.active_workspace or m.activeWorkspace
        if ws and ws.name == workspace.name then
          monitor_name = m.name
          return
        end
      end
    end
  end
end)

---The monitor the keyboard is on, as far as the compositor's events go.
---@return string?
function M.monitor()
  return monitor_name
end

---Claim the seat ahead of the event that confirms it.
---
---`mod+h/l` crossing onto a monitor with nothing to focus is the case: the
---compositor has nowhere to put the keyboard, so it may emit nothing at all
---and the seat would stay on the monitor being left -- with the opposite key
---then navigating that monitor and finding no way back. The next real event
---overwrites this.
---@param name string?
function M.claim(name)
  if name then
    monitor_name = name
  end
end

return M
