local toggle_minimize = require("hypr.lib.minimize")
local bind = require("hypr.lib.bind")
local submap = require("hypr.lib.submap")
local notify = require("hypr.lib.notify")
local qs = require("hypr.lib.qs")

-- === Audio controls ===
bind.audio("RaiseVolume", ",volume.sh --inc", "Volume up", nil, true)
bind.audio("LowerVolume", ",volume.sh --dec", "Volume down", nil, true)
bind.audio("Mute", ",volume.sh --toggle", "Mute output")
bind.audio("MicMute", ",volume.sh --toggle-mic", "Mute microphone")
bind.audio("Pause", ",player.sh --play-pause", "Media play/pause")
bind.audio("Play", ",player.sh --play-pause", "Media play/pause")
bind.audio("Prev", ",player.sh --prev", "Media previous track")
bind.audio("Next", ",player.sh --next", "Media next track")
bind.audio("RaiseVolume", ",player.sh --inc", "Media player volume up", { config.tertiary_mod }, true)
bind.audio("LowerVolume", ",player.sh --dec", "Media player volume down", { config.tertiary_mod }, true)

bind.brightness("Up", ",brightness.sh --inc")
bind.brightness("Down", ',brightness.sh --dec ""')

-- === Window management ===
--
-- Maximize was on SUPER+ALT+M, the same chord as minimize below. Hyprland keeps
-- the first registration, so minimize never fired and neither showed in the
-- cheatsheet, because none of the three carried a description. Maximize moves to
-- SUPER+ALT+X; the tests assert no root chord is claimed twice and that every
-- bind says what it does.
hl.bind(
  bind.parse_mods({ config.main_mod, config.tertiary_mod }) .. " + X",
  hl.dsp.window.fullscreen({ mode = "maximized" }),
  { description = "Maximize window", submap_universal = true }
)
hl.bind(
  bind.parse_mods({ config.main_mod, config.tertiary_mod }) .. " + F",
  hl.dsp.window.fullscreen({ mode = "fullscreen" }),
  { description = "Fullscreen window", submap_universal = true }
)
hl.bind(
  bind.parse_mods({ config.main_mod, config.tertiary_mod }) .. " + T",
  hl.dsp.window.float(),
  { description = "Toggle floating", submap_universal = true }
)

-- Closing a project terminal leaves its server running with nothing on screen
-- pointing at it, so `,proj.sh close-window` offers to take the project down
-- with the window (picker prompt; declining just closes the window). Any other
-- window closes straight away, exactly as `closewindow` did.
hl.bind(
  config.main_mod .. " + semicolon",
  hl.dsp.exec_cmd(",proj.sh close-window"),
  { description = "Close focused window (offers to kill its project)", submap_universal = true }
)

-- === The short path ===
--
-- The submap tree stays the discoverable route to everything. These four are the
-- ones walked daily, and two chords for an action you take fifty times a day is
-- one chord too many. Each keeps its entry in the tree, so nothing that already
-- lives in muscle memory stops working.
bind.exec("t", ",proj.sh pick", {
  description = "Open a project (picker)",
  submap_universal = true,
})

bind.exec("b", "uwsm app -- " .. config.apps.main_browser.cmd, {
  description = "Open the Browser",
  submap_universal = true,
})

-- SUPER+RETURN is a terminal, not a menu about terminals. The float and
-- project-shell variants keep the tree, one SHIFT away.
bind.exec("return", "uwsm app -- " .. config.apps.terminal.cmd, {
  description = "Open the Terminal",
})

submap.tree({
  mods = { config.main_mod, config.secondary_mod, "return" },
  name = "terminal",
  desc = "Terminal",
  entries = {
    bind.app_entry("return", config.apps.terminal, "Open the Terminal"),
    bind.app_entry("f", config.apps.terminal_float, "Open the floating Terminal", { config.main_mod }),
    -- No bare-tms entry: a terminal on the default tmux socket could host any
    -- project's session, which is exactly the cross-talk `,proj.sh` exists to
    -- prevent. Every tmux window comes from the project picker.
    bind.project_entry("s", "zsh", "Open a project on its shell window"),
  },
})

-- Projects. One picker (`,proj.sh`, whose list is scraped from the tms config,
-- so it and `C-b C-o` inside tmux always agree), and the key you press picks
-- which window of the project session the new client lands on.
submap.tree({
  mods = { config.main_mod, "p" },
  name = "project",
  desc = "Projects",
  entries = {
    -- No window name: the project's own template decides which tab it lands on
    -- (`.proj.toml` in the repo, or `[projects.<name>]` in the tms config).
    bind.project_entry("p", nil, "Open a project (its default window)"),
    bind.project_entry("n", "nvim", "Open a project on its nvim window"),
    bind.project_entry("s", "zsh", "Open a project on its shell window"),
    bind.project_entry("r", "run", "Open a project on its run window"),
    -- Plain open focuses the window the project already has; SHIFT says "a
    -- second terminal on it, please".
    bind.project_entry("p", nil, "Open a project in a new window", { config.secondary_mod }, true),
    -- Add another project to the window you are in instead of opening one: it
    -- joins this window's server (or, if it is already running elsewhere, the
    -- window moves to it), and `C-b C-s` switches between them.
    bind.project_entry("h", nil, "Attach another project to THIS window", nil, false, true),
    -- Teardown, in widening blast radius. `close` is the everyday one: it
    -- detaches this window's tmux client, so the window goes and the project
    -- keeps running. The two kills are behind SHIFT and ask in a picker
    -- first, since a keybind has no tty to prompt on.
    {
      key = "c",
      desc = "Close this window's project client (project keeps running)",
      action = hl.dsp.exec_cmd(",proj.sh close"),
    },
    {
      key = "k",
      mods = { config.secondary_mod },
      desc = "Kill the focused project (others on its server survive)",
      action = hl.dsp.exec_cmd(",proj.sh kill"),
    },
    {
      key = "k",
      mods = { config.secondary_mod, config.primary_mod },
      desc = "Kill every project server",
      action = hl.dsp.exec_cmd(",proj.sh kill-all"),
    },
  },
})

bind.exec("r", config.apps.app_launcher.cmd, {
  description = "Open Application Launcher",
})

submap.tree({
  mods = { config.main_mod, "a" },
  name = "applications",
  desc = "Applications",
  entries = {
    bind.app_entry("d", config.apps.media_browser, "Open Zen Browser media profile"),
    bind.app_entry("b", config.apps.main_browser, "Open the Browser"),
    bind.app_entry("d", config.apps.dev_browser, "Open the dev Browser", { config.primary_mod }),
    bind.app_entry("c", config.apps.calculator, "Open Calculator"),
    bind.app_entry("m", config.apps.password_manager, "Open Proton Pass"),
    bind.app_entry("f", config.apps.file_manager, "Open Yazi"),
    bind.app_entry("s", config.apps.package_manager_ui, "Open Shelly"),
    bind.app_entry("p", config.apps.package_manager_tui, "Open Shelly"),
  },
})

submap.tree({
  mods = { config.main_mod, "c" },
  name = "configuration",
  desc = "Configuration",
  entries = {
    bind.app_entry("b", config.apps.bluetooth_manager, "Open Bluetui"),
    bind.app_entry("v", config.apps.volume_control, "Open Wiremix"),
  },
})

submap.tree({
  mods = { config.main_mod, "w" },
  name = "special-ws",
  desc = "Special workspaces",
  entries = {
    bind.special_ws_entry("s", "music"),
    bind.special_ws_entry("v", "comms"),
    bind.special_ws_entry("l", "launcher"),
    bind.special_ws_entry("a", "ankama"),
  },
})

bind.focus_workspace("TAB", "e-1")
bind.focus_workspace("TAB", "e+1", { config.secondary_mod })

bind.bind_workspaces()

bind.layout_action({ config.main_mod, "j" }, "focus_up", "Move window focus up")
bind.layout_action({ config.main_mod, "k" }, "focus_down", "Move window focus down")

bind.layout_action({ config.main_mod, config.secondary_mod, "h" }, "swap_left", "Swap current with the left window")
bind.layout_action({ config.main_mod, config.secondary_mod, "l" }, "swap_right", "Swap current with the right window")
bind.layout_action({ config.main_mod, config.secondary_mod, "j" }, "swap_up", "Swap current with the window above")
bind.layout_action({ config.main_mod, config.secondary_mod, "k" }, "swap_down", "Swap current with the window below")

-- Layout messages, per layout, in a which-key submap tree:
--   SUPER+x  ->  d (dwindle) | m (master) | s (scrolling)  ->  layout op.
-- Each layout declares its own ops (see hypr/layouts/*); this just composes them
-- into groups, so it never needs touching when a layout gains a new op.
local layout_groups = {}
for _, ls in ipairs(require("hypr.lib.layout").get_submaps()) do
  layout_groups[#layout_groups + 1] = {
    key = ls.key,
    name = "layout-" .. ls.layout,
    desc = ls.layout,
    entries = ls.entries,
  }
end

submap.tree({
  mods = { config.main_mod, "m" },
  name = "layout",
  desc = "Layout messages",
  entries = layout_groups,
})

local function cycle_workspace_layout()
  local layouts = { "scrolling", "dwindle", "master", "monocle" }
  local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
  if not workspace then
    return
  end

  local next_layout = "dwindle"
  for i = 1, #layouts do
    if layouts[i] == workspace.tiled_layout then
      next_layout = layouts[(i % #layouts) + 1]
      break
    end
  end

  if workspace.special then
    hl.workspace_rule({ workspace = tostring(workspace.name), layout = next_layout })
  else
    hl.workspace_rule({ workspace = tostring(workspace.id), layout = next_layout })
  end
end

-- Repeatable on purpose: cycling layouts is a "try it and see" action, and
-- reopening a menu between tries is what made it feel like work.
hl.bind(config.main_mod .. " + x", cycle_workspace_layout, {
  description = "Cycle the workspace layout",
  submap_universal = true,
})

submap.tree({
  mods = { config.main_mod, config.secondary_mod, "r" },
  name = "window-management",
  desc = "Window management",
  entries = {
    bind.resize_entry("h", -10, 0),
    bind.resize_entry("l", 10, 0),
    bind.resize_entry("j", 0, -10),
    bind.resize_entry("k", 0, 10),
    bind.resize_entry("h", -20, 0, { config.tertiary_mod }),
    bind.resize_entry("l", 20, 0, { config.tertiary_mod }),
    bind.resize_entry("j", 0, -20, { config.tertiary_mod }),
    bind.resize_entry("k", 0, 20, { config.tertiary_mod }),
    { key = "e", desc = "Cycle the workspace layout", stay = true, action = cycle_workspace_layout },
  },
})

-- === Mouse bindings ===

hl.bind(
  config.main_mod .. " + " .. config.tertiary_mod .. " + mouse:272",
  hl.dsp.window.drag(),
  { description = "Move a window with left click", submap_universal = true, mouse = true }
)
hl.bind(config.main_mod .. " + " .. config.tertiary_mod .. " + m", function()
  toggle_minimize:toggle_minimize()
end, { description = "Minimize Window", submap_universal = true })

submap.tree({
  mods = { config.main_mod, "s" },
  name = "screencapture",
  desc = "Screen capture",
  entries = {
    {
      key = "s",
      name = "screen-shot",
      desc = "Screenshot",
      entries = {
        bind.screenshot_entry("w", "window", "Screenshot current window"),
        bind.screenshot_entry("o", "output", "Screenshot current output"),
        bind.screenshot_entry("r", "region", "Screenshot a selected region"),
      },
    },
    {
      key = "r",
      name = "screen-record",
      desc = "Screen record",
      entries = {
        bind.screenrecord_entry("r", "region", true, "Record a region (again to stop)"),
        bind.screenrecord_entry("o", "output", true, "Record current output (again to stop)"),
      },
    },
  },
})

-- === Utility ===

local kb_layouts = { "Dvorak (custom)", "Programmer Dvorak" }
local kb_idx = 1
bind.exec("space", function()
  hl.dispatch(hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))
  kb_idx = kb_idx % #kb_layouts + 1
  notify:notify("Keyboard layout: " .. kb_layouts[kb_idx], 2000, notify.level.INFO)
end, {
  description = "Toggle keyboard layout (dvorak-custom / programmer dvorak)",
  submap_universal = true,
  locked = true,
})

bind.exec("p", "hyprpicker -a -n", {
  no_main = true,
  mods = { config.tertiary_mod },
  description = "Execute hyprpicker to extract hex code",
})

bind.exec("slash", "qs -c quantumfate ipc call cheatsheet toggle", {
  description = "Show keybind cheatsheet",
  submap_universal = true,
})

-- Quickshell control: which-key menu exposing the rest of the shell's IPC
-- surface (theme, cheatsheet, team panel, store queries). Actions that take an
-- argument are reached elsewhere: `dofus select` via the team submap, and
-- `theme set <palette>` is covered here by `cycle`.
submap.tree({
  mods = { config.main_mod, "q" },
  name = "shell",
  desc = "Shell / Quickshell",
  entries = {
    -- (cheatsheet toggle is the global super+/ bind, which is submap_universal)
    {
      key = "p",
      desc = "Toggle team panel",
      action = function()
        qs.call("dofusPanel", "toggle")
      end,
    },
    {
      key = "r",
      desc = "Reload team store",
      action = function()
        qs.call("dofus", "reload")
      end,
    },
    {
      key = "n",
      desc = "Show roster",
      action = function()
        qs.notify("Dofus roster", "dofus", "team")
      end,
    },
    {
      key = "s",
      desc = "Selected team",
      action = function()
        qs.notify("Dofus team", "dofus", "selected")
      end,
    },
    {
      key = "t",
      desc = "Cycle theme",
      stay = true,
      action = function()
        qs.call("theme", "cycle")
      end,
    },
    {
      key = "i",
      desc = "Theme info",
      action = function()
        qs.notify("Theme", "theme", "get")
      end,
    },
    {
      key = "h",
      desc = "IPC help",
      action = function()
        qs.notify("Quickshell IPC", "help", "all")
      end,
    },
    {
      key = "m",
      desc = "Toggle system monitor",
      action = function()
        qs.call("sysmon", "toggle")
      end,
    },
    {
      key = "b",
      desc = "Toggle notifications",
      action = function()
        qs.call("notifications", "toggle")
      end,
    },
    {
      key = "d",
      desc = "Toggle do-not-disturb",
      stay = true,
      action = function()
        qs.call("notify", "dnd")
      end,
    },
  },
})
