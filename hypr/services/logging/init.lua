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

-- A log group's windows are `Log-<name>` kitties (`bin/,logs.sh`). They map
-- unfocused for the same reason a project's do: a group opens because a GROUP
-- was asked for, and letting each source's window take focus as it maps drags
-- the keyboard along behind the spawn order (hypr/windowrules.lua's
-- `project-window-no-steal`). `,logs.sh` focuses the group once, at the end.
hl.window_rule({
  name = "log-window-no-steal",
  match = { initial_class = "Log-[A-Za-z0-9_-]+" },
  no_initial_focus = true,
})

-- ...except the picker, which is a prompt: it wears the same class prefix and
-- would otherwise open without the keyboard (the mistake `Proj-picker` made).
hl.window_rule({
  name = "log-prompt-takes-focus",
  match = { initial_class = "Log-picker" },
  no_initial_focus = false,
})

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
    -- Declared log GROUPS (docs/logs.md): a document names a group's
    -- sources, `,logs.sh` instantiates it as one Hyprland group on this
    -- scene, and the deck column strips the groups one at a time. The
    -- `logview` entries above are the tmux-backed fixed journal views and
    -- stay until this has replaced what they do.
    { key = "o", desc = "Open a log group (picker)", action = hl.dsp.exec_cmd(",logs.sh pick") },
    {
      key = "d",
      mods = { config.secondary_mod },
      desc = "Close the focused log group",
      action = hl.dsp.exec_cmd(",logs.sh kill"),
    },
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
