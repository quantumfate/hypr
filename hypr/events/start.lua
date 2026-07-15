hl.on("hyprland.start", function()
	hl.exec_cmd("setxkbmap dvorak-custom")
	-- Quickshell desktop shell (team panel + future widgets). Replace any stale
	-- instance so a config reload restarts it cleanly.
	hl.exec_cmd("qs -c quantumfate kill >/dev/null 2>&1; qs -c quantumfate >/dev/null 2>&1 & disown")
end)
