-- The mode pointer watcher: converge the desk on what the pointer says.
--
-- Keyboard entry goes through `hyprfocus.enter`, which applies the
-- compositor's half directly. Every other writer only edits the pointer —
-- the shell's mood centre (Focus.set), a later schedule, `,hyprfocus seed`
-- resetting it — and none of those run in the compositor. This watcher is how
-- a pointer change reaches it: on every event the desk already reacts to, a
-- cheap mtime compare decides whether the pointer has moved, and apply
-- handles whichever mode it names.
--
-- Deliberately event-driven rather than timer-driven: an idle desk pays one
-- stat per event instead of paying a clock tick forever, and the compositor
-- runs it whether timers fire or not. The shell additionally drives the same
-- convergence when it writes the pointer (Focus.qml's mode change), so the
-- usual path does not even wait for the next event.
local notify = require("hypr.lib.notify")
local hyprfocus = require("hypr.hyprfocus.init")

local M = {}

--- The last error text notified, so a persistent failure reports once instead
--- of buzzing every event; a changed text notifies again.
local notified_err = nil
--- Apply the pointer's mode if it differs from the runtime's last application.
--- Converge, not enter: the pointer was written by whoever asked (it may
--- carry an expiry or provenance we must not clobber), and both halves still
--- run.
---@return string? mode the mode applied this call, or nil
---@return string? error
function M.tick()
  local pointer_mode = hyprfocus.active()
  if pointer_mode == hyprfocus.last_applied() then
    return nil, nil
  end
  local _, err = hyprfocus.converge(pointer_mode)
  if err then
    if err ~= notified_err then
      notified_err = err
      notify:notify("hyprfocus: " .. err, 5000, notify.level.ERROR)
    end
    return nil, err
  end
  notified_err = nil
  return pointer_mode, nil
end

-- The events a mode change is followed by: nothing here is about timing —
-- every subscription is a chance to notice the pointer moved. The stat costs
-- one mtime read; the store's mtime cache makes the compare O(1) while the
-- file does not change.
local EVENTS = { "workspace.active", "window.open", "window.close", "window.move_to_workspace" }

---Subscribe to the convergence triggers. Called once at config load.
function M.attach()
  for _, event in ipairs(EVENTS) do
    hl.on(event, function()
      M.tick()
    end)
  end
  -- The desk converged at load time: boot/first converge on the pointer's
  -- answer already covers a config loading under a stale pointer.
  M.tick()
end

return M
