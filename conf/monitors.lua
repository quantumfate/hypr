-- Monitors & monitor-bound persistent workspaces.
-- Ported from the formerly chezmoi-managed hypr-chezmoi/workspaces.conf.
--
-- MACHINE-SPECIFIC: this file replaces chezmoi templating. Edit the monitor
-- names / workspace assignments here per machine (or branch on hl.get_monitors()
-- if you later want auto-detection).

-- Default catch-all monitor configuration (auto resolution/position/scale).
hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = "auto",
})

-- DP-1 workspaces
hl.workspace_rule({ workspace = "1", monitor = "DP-1", persistent = true, default = true })
hl.workspace_rule({ workspace = "2", monitor = "DP-1", persistent = true })
hl.workspace_rule({ workspace = "3", monitor = "DP-1", persistent = true })
hl.workspace_rule({ workspace = "4", monitor = "DP-1", persistent = true })
hl.workspace_rule({ workspace = "5", monitor = "DP-1", persistent = true, gaps_in = 0, gaps_out = 0, border_size = 0 })

-- DP-2 workspaces
-- NOTE: the original config had a typo `layoutopt:rientation` (missing 'o') on
-- workspaces 6-9; corrected to `orientation` here so 6-9 match workspace 10.
for _, ws in ipairs({ "6", "7", "8", "9", "10" }) do
	hl.workspace_rule({
		workspace = ws,
		monitor = "DP-2",
		persistent = true,
		layout_opts = { orientation = "right", mfact = 0.5 },
	})
end
