-- The mode pointer watcher: converge the desk on what the pointer says.
--
-- Keyboard entry goes through `hyprfocus.enter`, which applies the
-- compositor's half directly. Every other writer only edits the pointer —
-- the shell's mood centre (Focus.set), a later schedule, `,hyprfocus seed`
-- resetting it — and none of those run in the compositor. This watcher is how
-- a pointer change reaches it: poll the pointer, and apply whichever mode it
-- names when that mode differs from the runtime's last-applied record.
--
-- One poll costs a mtime stat; the store re-reads only on change, so an idle
-- desk pays nothing worth measuring. An apply error is notified once per
-- distinct text and does not advance the record: the next tick retries, so a
-- bad declaration fails over and over rather than silently diverging from
-- the desk it describes.
local notify = require("hypr.lib.notify")
local hypr = require("hypr.lib.hypr")
local hyprfocus = require("hypr.hyprfocus.init")

local WATCH_MS = 2000

local M = {}

--- The last error text notified, so a persistent failure reports once instead
--- of buzzing every tick; a changed text notifies again.
local notified_err = nil

--- Apply the pointer's mode if it differs from the runtime's last application.
--- Converge, not enter: the pointer was written by whoever asked (it may
--- carry an expiry or provenance we must not clobber), and both halves still
--- run.
---@return string? mode the mode applied this tick, or nil
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

--- Start the poll loop. Each tick re-arms a one-shot timer, which keeps the
--- cadence data rather than API knowledge.
function M.arm()
  local function loop()
    M.tick()
    hypr.oneshot(WATCH_MS, loop)
  end
  hypr.oneshot(WATCH_MS, loop)
end

return M
