hl.on("hyprland.start", function()
  hl.exec_cmd("setxkbmap dvorak-custom")
  -- Quickshell desktop shell (team panel + future widgets). Launched via
  -- `uwsm app` so it runs in its own systemd scope with the finalized session
  -- environment (uwsm manages this session). Replace any stale instance first.
  hl.exec_cmd("qs -c quantumfate kill >/dev/null 2>&1; uwsm app -- qs -c quantumfate >/dev/null 2>&1")
end)
