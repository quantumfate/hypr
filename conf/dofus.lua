-- Dofus gaming window rules & submaps.
-- Ported from the formerly chezmoi-managed dofus-binds.conf.
--
-- MACHINE-SPECIFIC: only relevant on machines where you play Dofus. The bound
-- scripts live in an external repo (gitlab/quantumfate/dofus-scripts).

local mainMod       = "SUPER"
local dofus_scripts = "~/.local/share/own-scripts/gitlab/quantumfate/dofus-scripts"
local toggle_submap = "~/.config/hypr/scripts/toggle_submap.sh"

-- Window rules
hl.window_rule({
  match          = { initial_class = "Dofus.x64" },
  workspace      = "5",
  float          = true,
  center         = true,
  content        = "game",
  opacity        = "1.0 override",
  no_anim        = true,
  suppress_event = "fullscreen",
})
hl.window_rule({
  match     = { initial_class = "Ankama Launcher" },
  workspace = "5",
  center    = true,
  size      = {2000, 1200},
  float     = true,
})
hl.window_rule({
  match     = { class = "Ankama Launcher", title = "overlay" },
  workspace = "5",
  float     = true,
  center    = true,
  tag       = "+floating-window",
})

-- Enter the Dofus submap
hl.bind(mainMod .. " + d", hl.dsp.exec_cmd(toggle_submap .. ' --on "Dofus:dofus:reset"'))

hl.define_submap("dofus", function()
  hl.bind("escape",     hl.dsp.exec_cmd(toggle_submap .. ' --off "Dofus:dofus:reset"'))
  hl.bind("d",          hl.dsp.exec_cmd(dofus_scripts .. "/dofus_toggle_launch.sh"))
  hl.bind("a",          hl.dsp.exec_cmd(dofus_scripts .. "/dofus_toggle_launch.sh --team-leech"))
  -- Auto turn-swap detector (toggle)
  hl.bind("s",          hl.dsp.exec_cmd(dofus_scripts .. "/dofus_swap_toggle.sh"))
  hl.bind("SHIFT + s",  hl.dsp.exec_cmd(dofus_scripts .. "/dofus_swap_toggle.sh --team-leech"))
  -- Enter the team_pioneer submap
  hl.bind("plus",       hl.dsp.exec_cmd(toggle_submap .. ' --on "Dofus:team_pioneer:dofus"'))
end)

hl.define_submap("team_pioneer", function()
  for i = 1, 8 do
    hl.bind("F" .. i, hl.dsp.exec_cmd(dofus_scripts .. "/wrap_action.sh --activate " .. (i - 1)))
  end
  -- Scroll direction is inverted
  hl.bind("F23",               hl.dsp.exec_cmd(dofus_scripts .. "/wrap_action.sh --down --pioneer"))
  hl.bind(mainMod .. " + F23", hl.dsp.exec_cmd(dofus_scripts .. "/wrap_action.sh --up --pioneer"))
  hl.bind("right",             hl.dsp.exec_cmd(dofus_scripts .. "/wrap_action.sh --down --pioneer"))
  hl.bind("left",              hl.dsp.exec_cmd(dofus_scripts .. "/wrap_action.sh --up --pioneer"))
  hl.bind("mouse:274",         hl.dsp.exec_cmd(dofus_scripts .. "/wrap_action.sh --press --pioneer"))
  hl.bind("SHIFT + escape",    hl.dsp.exec_cmd(toggle_submap .. ' --off "Dofus:team_pioneer:dofus"'))
  hl.bind(mainMod .. " + F10", hl.dsp.exec_cmd("bash " .. dofus_scripts .. "/double_click.sh &"))
  hl.bind(mainMod .. " + F11", hl.dsp.exec_cmd("pkill -f double_click.sh"), { release = true, transparent = true })
end)
