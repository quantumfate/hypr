-- Alt-Tab window switcher (ported from conf/misc/alt-tab.conf).
--
-- NOTE: the alttab scripts call `hyprctl dispatch sendshortcut ...` (legacy
-- syntax). In Hyprland 0.55+ `hyprctl dispatch` expects Lua, e.g.
--   hyprctl dispatch 'hl.dsp.send_shortcut({ key = "return", window = "class:alttab" })'
-- Update scripts/alttab/*.sh if alt-tab misbehaves.

-- Enter the switcher (works inside any submap thanks to submap_universal).
hl.bind("ALT + TAB",         hl.dsp.exec_cmd("$HOME/.config/hypr/scripts/alttab/enable.sh 'down'"), { submap_universal = true })
hl.bind("ALT + SHIFT + TAB", hl.dsp.exec_cmd("$HOME/.config/hypr/scripts/alttab/enable.sh 'up'"),   { submap_universal = true })

hl.define_submap("alttab", function()
  hl.bind("ALT + tab",         hl.dsp.send_shortcut({ mods = "",      key = "tab", window = "class:alttab" }))
  hl.bind("ALT + SHIFT + tab", hl.dsp.send_shortcut({ mods = "shift", key = "tab", window = "class:alttab" }))

  hl.bind("ALT + ALT_L",          hl.dsp.exec_cmd("$XDG_CONFIG_HOME/hypr/scripts/alttab/disable.sh ; hyprctl -q dispatch sendshortcut , return,class:alttab"), { release = true, transparent = true })
  hl.bind("ALT + SHIFT + ALT_L",  hl.dsp.exec_cmd("$XDG_CONFIG_HOME/hypr/scripts/alttab/disable.sh ; hyprctl -q dispatch sendshortcut , return,class:alttab"), { release = true, transparent = true })
  hl.bind("ALT + Return",         hl.dsp.exec_cmd("$XDG_CONFIG_HOME/hypr/scripts/alttab/disable.sh ; hyprctl -q dispatch sendshortcut , return, class:alttab"))
  hl.bind("ALT + SHIFT + Return", hl.dsp.exec_cmd("$XDG_CONFIG_HOME/hypr/scripts/alttab/disable.sh ; hyprctl -q dispatch sendshortcut , return, class:alttab"))
  hl.bind("ALT + escape",         hl.dsp.exec_cmd("$XDG_CONFIG_HOME/hypr/scripts/alttab/disable.sh ; hyprctl -q dispatch sendshortcut , escape,class:alttab"))
  hl.bind("ALT + SHIFT + escape", hl.dsp.exec_cmd("$XDG_CONFIG_HOME/hypr/scripts/alttab/disable.sh ; hyprctl -q dispatch sendshortcut , escape,class:alttab"))
end)

hl.workspace_rule({ workspace = "special:alttab", gaps_out = 0, gaps_in = 0, border_size = 0 })

hl.window_rule({ match = { class = "alttab" }, no_anim      = true })
hl.window_rule({ match = { class = "alttab" }, stay_focused = true })
hl.window_rule({ match = { class = "alttab" }, workspace    = "special:alttab" })
hl.window_rule({ match = { class = "alttab" }, border_size  = 0 })
