local Store = require("hypr.lib.store")

-- Same desk every morning: whichever project carries `study` in projects.json
-- gets opened (its own window template decides the nvim window). Purely a
-- convenience on top of two stores that may not exist yet on a fresh
-- checkout — either one missing just means this step does nothing, silently.
local function open_study_project()
  local projects = Store.define("projects"):get("projects")
  local study_name = nil
  for name, meta in pairs(projects or {}) do
    if type(meta) == "table" and meta.study then
      study_name = name
      break
    end
  end
  if not study_name then
    return
  end

  -- Focus mode blocks distractions, not the thing it exists for — a leftover
  -- "focus" from last night just gets a heads-up, never a reason to skip this.
  local focus = Store.define("focus"):get()
  if focus and focus.mode == "focus" then
    hl.exec_cmd("notify-send 'focus' 'still on from last session' >/dev/null 2>&1")
  end

  -- `,proj.sh` (not this file) is the only thing that knows a project's path
  -- — projects.json deliberately doesn't carry one, see its schema — so the
  -- name is resolved through its own `list` rather than duplicating the scan.
  local cmd = (
    "path=$(,proj.sh list | awk -F'\\t' -v n=%s '$1==n{print $2; exit}'); "
    .. '[ -n "$path" ] && ,proj.sh open "$path" >/dev/null 2>&1'
  ):format(("%q"):format(study_name))
  hl.exec_cmd(cmd)
end

hl.on("hyprland.start", function()
  hl.exec_cmd("setxkbmap dvorak-custom")
  -- Quickshell desktop shell (team panel + future widgets). Launched via
  -- `uwsm app` so it runs in its own systemd scope with the finalized session
  -- environment (uwsm manages this session). Replace any stale instance first.
  hl.exec_cmd("qs -c quantumfate kill >/dev/null 2>&1; uwsm app -- qs -c quantumfate >/dev/null 2>&1")
  open_study_project()
end)
