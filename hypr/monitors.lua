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
