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
-- The same module name every other caller uses: requiring it by its file path
-- (`hypr.hyprfocus.init`) loads a SECOND copy with its own apply guard, held
-- record and applied desk, which let a watcher tick nest a whole apply inside
-- another and drop held windows from the record.
local hyprfocus = require("hypr.hyprfocus")

local M = {}

--- The last error text notified, so a persistent failure reports once instead
--- of buzzing every event; a changed text notifies again.
local notified_err = nil
--- A tick skipped mid-apply retries after this long. The skip drops the
--- event, but not the drift that caused it: a timed mode expiring into
--- `previous` or a shell pointer write lands while the apply is running, and
--- the next event may never come (the settle's focus can be a no-op). One
--- armed retry at a time; it re-arms itself while the apply is still going.
local retry_timer = nil
local RETRY_MS = 200
--- Apply the pointer's mode if it differs from the runtime's last application.
--- Converge, not enter: the pointer was written by whoever asked (it may
--- carry an expiry or provenance we must not clobber), and both halves still
--- run.
---@return string? mode the mode applied this call, or nil
---@return string? error
function M.tick()
  -- An apply's own moves raise these events; converging from inside it
  -- would nest a second apply into the first.
  if hyprfocus.applying() then
    if not retry_timer then
      retry_timer = require("hypr.lib.hypr").oneshot(RETRY_MS, function()
        retry_timer = nil
        M.tick()
      end)
    end
    return nil, nil
  end
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
  -- A monitor coming back re-places scenes that fell back to primary while it
  -- was gone; the mode's role, not the fallback, is where they belong.
  hl.on("monitor.added", function()
    hyprfocus.replace()
  end)
  -- The desk converged at load time: boot/first converge on the pointer's
  -- answer already covers a config loading under a stale pointer.
  M.tick()
end

return M
