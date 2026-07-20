-- NotifyWrapper — routes WM feedback (swap on/off, launch enable, layout hints)
-- through the Quickshell notification daemon instead of Hyprland's internal
-- overlay. These are all transient: shown once, never kept in history.
-- Public API is unchanged (text, duration, level) so call sites need no edits.
---@class NotifyWrapper
local M = {}

---@enum NotifyLevel
M.level = {
  INFO = "INFO",
  WARNING = "WARNING",
  ERROR = "ERROR",
}

-- WM levels → the shell's toast levels (it has no distinct "warning").
local qs_level = {
  INFO = "info",
  WARNING = "info",
  ERROR = "error",
}

---@param text string
---@param _duration integer unused — the daemon owns toast lifetime (kept for API compat)
---@param level NotifyLevel
function M:notify(text, _duration, level)
  local lvl = qs_level[level] or "info"
  -- Transient `notify toast`: feedback-only, excluded from history.
  hl.exec_cmd(("qs -c quantumfate ipc call notify toast %q %q"):format(text, lvl))
end

M.__index = M

return M
