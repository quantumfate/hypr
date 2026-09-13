--- Window-placement diagnosis command (LEO-213). Prints, for every open
--- window, which rules match it, what workspace the rules claim, and where the
--- window actually is. Runs on demand (shell submap key x).
local diagnose = require("hypr.lib.diagnose")

local M = {}

---@return string path of the full report
function M.write_report(report)
  local path = "/tmp/hypr-window-diagnosis.txt"
  local f = assert(io.open(path, "w"))
  f:write(report, "\n")
  f:close()
  return path
end

function M.run()
  local report = diagnose.report(hl.get_windows(), diagnose.rules)
  M.write_report(report)
  -- Notify the full report (the shell's notification centre renders it), and
  -- keep the file as the canonical, diffable copy.
  hl.exec_cmd(("notify-send 'Window placement' %q"):format(report))
end

return M
