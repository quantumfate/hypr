-- Logging workspace: the window rules, the workspace binding and the `logs`
-- submap for the log viewer owned by system-config's `zsh` role.
local submap = require("hypr.lib.submap")
local windowrule = require("hypr.lib.windowrule")

local WORKSPACE = "name:logs"

-- Command surface. `logview <spec>` opens the source in the isolated server and
-- raises the kitty window; the spec vocabulary is logstream's (see its header).
local viewer = "logview"
local function open(spec)
  local cmd = ("uwsm app -- %s %s"):format(viewer, spec or "")
  -- extra parens: gsub returns (string, count) and exec_cmd takes one argument
  return hl.dsp.exec_cmd((cmd:gsub("%s+$", "")))
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

submap.tree({
  mods = { config.main_mod, "l" },
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
