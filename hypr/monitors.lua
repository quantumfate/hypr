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

-- e2e-only, opt-in: the nested harness's default output is tiny (fast, and
-- plenty for compositor-only assertions), too small to fit a real bar's
-- three islands without them overlapping. `hyprctl keyword`/`monitorv2`
-- against a running instance is a confirmed no-op on this Lua-config build
-- ("unknown request") -- sizing has to happen at config load, here, before
-- Hyprland locks in the output's mode; a later per-output rule overrides an
-- earlier wildcard one for the same output. QF_E2E_BIG_MONITOR=1 opts a
-- scenario in; unset, every other scenario keeps today's small/fast output.
if os.getenv("QF_E2E") == "1" and os.getenv("QF_E2E_BIG_MONITOR") == "1" then
  hl.monitor({
    output = "WAYLAND-1",
    mode = "1920x480@60",
    position = "0x0",
    scale = "1",
  })
end
