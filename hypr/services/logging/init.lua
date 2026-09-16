-- Logging workspace: the window rules, the workspace binding and the `logs`
-- submap for the log viewer owned by system-config's `zsh` role.
local submap = require("hypr.lib.submap")
local windowrule = require("hypr.lib.windowrule")

local WORKSPACE = "name:logs"

-- Command surface. `logview <spec>` opens the source in the isolated server and
-- raises the kitty window; the spec vocabulary is logstream's (see its header).
local viewer = "logview"
-- Focus FIRST, then open. Without the focus the viewer window is updated on a
-- workspace you are not looking at, which is indistinguishable from a dead
-- keybind. With it, every entry lands you in front of the result: the
-- workspace comes forward and the source opens in its own tmux window.
local function open(spec)
  local cmd = ("uwsm app -- %s %s"):format(viewer, spec or "")
  -- extra parens: gsub returns (string, count) and exec_cmd takes one argument
  local exec = hl.dsp.exec_cmd((cmd:gsub("%s+$", "")))
  return function()
    hl.dispatch(hl.dsp.focus({ workspace = WORKSPACE }))
    hl.dispatch(exec)
  end
end

-- `logview`'s spec vocabulary has no generic "journal filtered by
-- SYSLOG_IDENTIFIER" source (its specs are `unit:`/`user:` — a systemd unit —
-- or the fixed severity/boot views), and the hyprfocus lifecycle log
-- (LEO-352) isn't a unit: it's `trace.lua` writing journal entries tagged
-- `SYSLOG_IDENTIFIER=hyprfocus` directly. So this raises a plain kitty on the
-- logs workspace running the query command instead of going through
-- `logview`, same class tag and workspace rule as the viewer itself.
local function open_hyprfocus()
  local cmd = "uwsm app -- kitty --class logviewer --title hyprfocus -e ,hyprfocus log --follow"
  local exec = hl.dsp.exec_cmd(cmd)
  return function()
    hl.dispatch(hl.dsp.focus({ workspace = WORKSPACE }))
    hl.dispatch(exec)
  end
end

windowrule.tag_props({
  { initial_class = "(logviewer)" },
}, "+logs")

windowrule.tag_set_effects("logs", {
  static = {
    workspace = WORKSPACE,
    float = false,
    rounding = 0,
  },
  dynamic = {
    opacity = "1 override 1 override",
  },
})

-- SUPER+e, NOT SUPER+l: `l` is already the hjkl "focus right" bind. A duplicate
-- root keybind fails silently — Hyprland keeps both, so the press moves focus
-- AND enters the submap, after which every other bind looks dead because the
-- compositor is sitting inside a submap. Check new root binds with:
--   hyprctl binds -j | jq -r '.[]|select(.submap=="" and .modmask==64).key' | sort | uniq -d
submap.tree({
  mods = { config.main_mod, "e" },
  name = "logs",
  desc = "Logs",
  entries = {
    { key = "l", desc = "Pick a log source", action = open() },
    { key = "e", desc = "Errors this boot", action = open("errors") },
    { key = "w", desc = "Warnings this boot", action = open("warnings") },
    { key = "k", desc = "Kernel ring buffer", action = open("kernel") },
    { key = "f", desc = "Live journal", action = open("follow") },
    { key = "b", desc = "This boot, from the top", action = open("boot") },
    { key = "p", desc = "Previous boot", action = open("prev") },
    { key = "a", desc = "Audit / denials", action = open("audit") },
    { key = "h", desc = "hyprfocus decisions", action = open_hyprfocus() },
    {
      key = "g",
      desc = "Go to the logs workspace",
      action = hl.dsp.focus({ workspace = WORKSPACE }),
    },
    {
      key = "x",
      desc = "Close all log sessions",
      action = hl.dsp.exec_cmd("tmux -L logs kill-server"),
    },
  },
})
