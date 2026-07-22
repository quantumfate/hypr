-- Quickshell IPC helper. Thin wrapper over `qs -c <config> ipc call …` so
-- keybinds can drive the running shell (windows, theme, queries). Commands are
-- fire-and-forget (never block the compositor). See the quickshell repo's
-- services/*.qml IpcHandlers and modules/common/IpcHelp.qml for the surface.
local M = {}

M.config = "quantumfate"

---@return string base `qs -c <config> ipc call ` command prefix
local function base()
  return "qs -c " .. M.config .. " ipc call "
end

---Call an IPC function (fire-and-forget). Extra args are appended, each shell-
---quoted so names with spaces survive.
---@param target string
---@param fn string
---@param ... string? optional positional arguments
function M.call(target, fn, ...)
  local cmd = base() .. target .. " " .. fn
  for _, arg in ipairs({ ... }) do
    cmd = cmd .. " " .. ("%q"):format(arg)
  end
  hl.exec_cmd(cmd)
end

---Call an IPC query and show its stdout as a desktop notification.
---@param title string notification summary
---@param target string
---@param fn string
function M.notify(title, target, fn)
  -- Command substitution captures the IPC stdout into the notification body.
  hl.exec_cmd(('notify-send %q "$(%s%s %s)"'):format(title, base(), target, fn))
end

return M
