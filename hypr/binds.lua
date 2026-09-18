local toggle_minimize = require("hypr.lib.minimize")
local bind = require("hypr.lib.bind")
local submap = require("hypr.lib.submap")
local layout_lib = require("hypr.lib.layout")
local notify = require("hypr.lib.notify")
local qs = require("hypr.lib.qs")
local focus_gate = require("hypr.lib.focus_gate")
local diag = require("hypr.services.diag")
local hyprfocus_binds = require("hypr.hyprfocus.binds")

-- Focus mode is data + an oracle (Focus.qml on the shell side,
-- hypr/lib/focus_gate.lua here): the store is the truth both read, so the
-- check runs at DISPATCH time without a subprocess — a store read on the
-- mtime cache instead of a spawned `qs ipc` per press (LEO-267). Toggling
-- focus still needs no reload: the next press reads the new pointer.
-- Fails open: no policy, no pointer, a lapsed expiry all mean "proceed".
---@param kind "media"|"game"
---@return string? reason non-nil when focus mode blocks this kind
local function focus_block_reason(kind)
  return focus_gate.block_reason(kind)
end

-- Scene reachability: the mood can name a workspace scene "blocked", which
-- prevents ENTERING it (a session already running is never torn down — same
-- firm semantics the launcher gate uses). Same store read, fails open.
---@param scene string
---@return string? reason non-nil when the scene is blocked
local function scene_block_reason(scene)
  return focus_gate.blocked_scene(scene)
end

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
hyprfocus_binds.bind(
  bind.parse_mods({ config.main_mod, config.tertiary_mod }) .. " + X",
  hl.dsp.window.fullscreen({ mode = "maximized" }),
  { description = "Maximize window", submap_universal = true }
)
hyprfocus_binds.bind(
  bind.parse_mods({ config.main_mod, config.tertiary_mod }) .. " + F",
  hl.dsp.window.fullscreen({ mode = "fullscreen" }),
  { description = "Fullscreen window", submap_universal = true }
)
hyprfocus_binds.bind(
  bind.parse_mods({ config.main_mod, config.tertiary_mod }) .. " + T",
  hl.dsp.window.float(),
  { description = "Toggle floating", submap_universal = true }
)

-- Closing a project terminal leaves its server running with nothing on screen
-- pointing at it, so `,proj.sh close-window` offers to take the project down
-- with the window (picker prompt; declining just closes the window). Any other
-- window closes straight away, exactly as `closewindow` did.
hyprfocus_binds.bind(
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
  name = "applications",
  desc = "Applications",
  entries = {
    -- Guarded, not bind.app_entry: focus mode blocks this launch (never a
    -- session already running — there isn't one, a browser profile is just a
    -- window), so the check has to run here instead of at build time.
    {
      key = "d",
      desc = "Open Zen Browser media profile",
      action = function()
        local reason = focus_block_reason("media") or scene_block_reason("media")
        if reason then
          notify:notify("Blocked: " .. reason, 3000, notify.level.WARNING)
          return
        end
        hl.dispatch(hl.dsp.exec_cmd("uwsm app -- " .. config.apps.media_browser.cmd))
      end,
    },
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
  name = "configuration",
  desc = "Configuration",
  entries = {
    bind.app_entry("b", config.apps.bluetooth_manager, "Open Bluetui"),
    bind.app_entry("v", config.apps.volume_control, "Open Wiremix"),
  },
})

-- Shelves: one key per app in a single submap. Shelves carrying a `tree`
-- (Ankama Launcher, Steam, Lutris) are admitted by the mode, so their keys
-- exist only where the mode enables them.
do
  local shelf = require("hypr.lib.shelf")
  local entries = {}
  for _, s in ipairs(config.shelves) do
    entries[#entries + 1] = shelf.entry(s)
  end
  submap.tree({ name = "shelf", desc = "Shelves", entries = entries })
end

bind.bind_workspace_cycle()

-- The media guard used to live here as a separate block ahead of
-- bind_workspaces() (Hyprland keeps the first registration for a chord). It
-- is gone (LEO-344): workspace-row keys are positional now (Nth scene on the
-- focused monitor, resolved at press time from the applied desk), so a mode
-- that does not place "media" on the focused monitor already makes its key a
-- no-op — there is no fixed "media" chord left to guard. Focus mode's
-- media-launch guard (`applications` submap, "d") is the meaningful target
-- that survives; it blocks OPENING the browser, which a workspace key alone
-- never does.
bind.bind_workspace_row()

-- Scene tile/window navigation (LEO-344 decision comment). `mod+h/l` moves
-- across tiles in the scene layout's own left-to-right order, continuing
-- onto the adjacent monitor at the edge; `mod+j/k` moves within the focused
-- tile (a group's members, or a stacked block's windows). Off a scene
-- workspace (scrolling), these fall back to the layout's own directional
-- focus/swap, which is what these chords did before.
do
  local nav = require("hypr.lib.nav")
  local scene_spec = require("hypr.scene.spec")
  local scene_provider = require("hypr.scene.provider")
  local scene_order = require("hypr.scene.order")
  local group_adapters = require("hypr.scene.group_adapters")
  local grouping = require("hypr.scene.grouping")

  ---`nav.tile_order`'s `opts.enter`: the group's adapter picks the entry
  ---member (LEO-380 follow-up), by the class any member already names.
  ---@param members Scene.Tile[]
  ---@param group_key string
  ---@return string?
  local function group_enter(members, group_key)
    local class = members[1] and members[1].class
    return group_adapters.for_class(class).enter(members, { group_key = group_key })
  end
  local tile_opts = { enter = group_enter }

  ---@return HL.Window?, Scene.Spec?
  local function focused_scene()
    local w = hl.get_active_window()
    if not w or not w.workspace then
      return w, nil
    end
    return w, scene_spec.load()[w.workspace.name]
  end

  ---The monitor adjacent to `monitor` in `dir`, or nil — the shared lookup
  ---both branches of `focus_tile` cross to.
  ---@param monitor table
  ---@param dir "left"|"right"
  ---@return table?
  local function adjacent_monitor(monitor, dir)
    -- Ignored monitors are never crossed onto.
    local ordered = nav.monitor_order(nav.usable_monitors(hl.get_monitors() or {}, config.host.ignored_monitors))
    return nav.adjacent_monitor(ordered, monitor.name, dir)
  end

  ---`mod+h`/`mod+l`: gather both monitors' state and hand it to the pure
  ---decision (`hypr/lib/nav.lua` `M.decide`, LEO-380). Reading the focused
  ---workspace from `hl.get_active_workspace()` rather than the active
  ---window's own workspace is what lets this run from an empty workspace,
  ---where there is no active window to read a workspace off at all
  ---(`hl.get_active_monitor()`'s object never populates `activeWorkspace` —
  ---unlike an entry from `hl.get_monitors()` — so that field is not a route
  ---to it either).
  ---@param dir "left"|"right"
  local function focus_tile(dir)
    local monitor = hl.get_active_monitor()
    if not monitor then
      return
    end
    local ws_name = (hl.get_active_workspace() or {}).name
    local scene = ws_name and scene_spec.load()[ws_name]
    local w = hl.get_active_window()

    if not scene then
      if not w then
        return
      end
      -- Off a scene workspace (scrolling): try the layout's own directional
      -- focus first. If it left the active window unchanged — there was
      -- nothing that way on this monitor — cross to the adjacent monitor
      -- instead of stranding focus at the edge (LEO-372: DP-2's edge tile
      -- had no window to the right of it).
      local before = hl.get_active_window()
      layout_lib.dispatch(dir == "left" and "focus_left" or "focus_right")
      local after = hl.get_active_window()
      if nav.focus_unchanged(before and before.address, after and after.address) then
        local adjacent = adjacent_monitor(monitor, dir)
        if adjacent then
          hl.dispatch(hl.dsp.focus({ monitor = adjacent.name }))
        end
      end
      return
    end

    local tiles = nav.tile_order(scene, scene_provider.workspace_tiles(scene.name), tile_opts)
    local monitors = hl.get_monitors() or {}
    local ordered = nav.monitor_order(nav.usable_monitors(monitors, config.host.ignored_monitors))
    local adjacent = nav.adjacent_monitor(ordered, monitor.name, dir)
    -- What the adjacent monitor already shows, so `decide` can pick its edge
    -- tile without a second round of dispatches — nil when there is no
    -- adjacent monitor at all, an empty `target` when it has no scene tiles
    -- (decide's cue to focus the monitor itself, per the decision comment).
    local target
    if adjacent then
      local active = adjacent.activeWorkspace
      local other_scene = active and active.name and scene_spec.load()[active.name]
      target = {
        tiles = other_scene
            and nav.tile_order(other_scene, scene_provider.workspace_tiles(other_scene.name), tile_opts)
          or {},
      }
    end

    local action = nav.decide({
      monitors = monitors,
      ignored = config.host.ignored_monitors,
      focused = monitor.name,
      tiles = tiles,
      active = w and w.address,
      dir = dir,
      target = target,
    })
    if action.kind == "window" then
      hl.dispatch(hl.dsp.focus({ window = "address:" .. action.address }))
    elseif action.kind == "monitor" then
      hl.dispatch(hl.dsp.focus({ monitor = action.name }))
    end
  end

  ---A group's live members as `{ address, title }`, normalized the way
  ---every other group reader here does (`hl.get_window().group.members` is a
  ---bare window, not a one-element array, when the group holds exactly one).
  ---@param group HL.Group
  ---@return { address: string, title: string? }[]
  local function group_members(group)
    local raw = group.members
    raw = (raw and raw.title) and { raw } or (raw or {})
    local members = {}
    for _, m in ipairs(raw) do
      members[#members + 1] = { address = m.address, title = m.title }
    end
    return members
  end

  ---`mod+j`/`mod+k` on a grouped tile: next/prev in the group's adapter
  ---order (LEO-380), wrapping, focusing by address — not the native
  ---`hl.dsp.group.next/prev` tab step, which follows Hyprland's own order
  ---instead of the adapter's (the Dofus roster, or default join order).
  ---@param w HL.Window
  ---@param dir "next"|"prev"
  local function focus_in_group(w, dir)
    local order = group_adapters.for_class(w.class).order(group_members(w.group), { group_key = grouping.group_key(w) })
    local index
    for i, address in ipairs(order) do
      if address == w.address then
        index = i
      end
    end
    if not index or #order < 2 then
      return
    end
    local step = dir == "next" and 1 or -1
    local target = order[((index - 1 + step) % #order) + 1]
    hl.dispatch(hl.dsp.focus({ window = "address:" .. target }))
  end

  ---@param dir "next"|"prev"
  local function focus_window_in_tile(dir)
    local w, scene = focused_scene()
    if not w then
      return
    end
    if not scene then
      layout_lib.dispatch(dir == "next" and "focus_down" or "focus_up")
      return
    end
    if w.group then
      focus_in_group(w, dir)
      return
    end
    local tiles = nav.tile_order(scene, scene_provider.workspace_tiles(scene.name), tile_opts)
    local index = nav.tile_index(tiles, w.address)
    local tile = index and tiles[index]
    if not tile then
      return
    end
    local target = nav.window_neighbor(tile.addresses, w.address, dir)
    if target then
      hl.dispatch(hl.dsp.focus({ window = "address:" .. target }))
    end
  end

  ---@param dir "left"|"right"
  local function swap_tile(dir)
    local w, scene = focused_scene()
    if not w then
      return
    end
    if not scene then
      layout_lib.dispatch(dir == "left" and "swap_left" or "swap_right")
      return
    end
    local tiles = nav.tile_order(scene, scene_provider.workspace_tiles(scene.name), tile_opts)
    local index = nav.tile_index(tiles, w.address)
    if not index then
      return
    end
    local new_order = nav.swap_order(tiles, index, dir)
    if not new_order then
      return
    end
    -- Session-only (hypr/scene/order.lua): the layout provider reads this on
    -- its next recalculate. Nothing here writes $QF_STORE or a scene
    -- declaration — a swap is how the desk looks right now, not an edit.
    scene_order.set(scene.name, new_order)
    -- Re-asserting focus on the window already focused is not a focus-dance
    -- (nothing else is focused meanwhile); it just gives the compositor a
    -- change to react to, so the swapped order actually gets laid out.
    hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address }))
  end

  ---mod+shift+j/k: move the focused window forward/back within its group.
  ---Only meaningful for a grouped tile (the decision names "within its
  ---group" specifically); a stacked non-group block has no such order to
  ---change here, so it is a no-op.
  ---@param dir "forward"|"back"
  local function move_in_group(dir)
    local w = hl.get_active_window()
    if not w or not w.group then
      return
    end
    -- movegroupwindow takes a bare "f"/"b" argument, acting on the focused
    -- window's own group — no focus-dance, since that window is already
    -- focused by definition of "its group".
    hl.dispatch(hl.dsp.movegroupwindow(dir == "forward" and "f" or "b"))
  end

  bind.exec("h", function()
    focus_tile("left")
  end, { description = "Focus the tile to the left", submap_universal = true })
  bind.exec("l", function()
    focus_tile("right")
  end, { description = "Focus the tile to the right", submap_universal = true })
  bind.exec("j", function()
    focus_window_in_tile("next")
  end, { description = "Focus the next window in this tile", submap_universal = true })
  bind.exec("k", function()
    focus_window_in_tile("prev")
  end, { description = "Focus the previous window in this tile", submap_universal = true })

  bind.exec("h", function()
    swap_tile("left")
  end, {
    mods = { config.secondary_mod },
    description = "Swap this tile with the one to the left",
    submap_universal = true,
  })
  bind.exec("l", function()
    swap_tile("right")
  end, {
    mods = { config.secondary_mod },
    description = "Swap this tile with the one to the right",
    submap_universal = true,
  })
  bind.exec(
    "j",
    function()
      move_in_group("forward")
    end,
    { mods = { config.secondary_mod }, description = "Move this window forward in its group", submap_universal = true }
  )
  bind.exec("k", function()
    move_in_group("back")
  end, { mods = { config.secondary_mod }, description = "Move this window back in its group", submap_universal = true })
end

-- Layout messages, per layout, in a which-key submap tree:
--   SUPER+x  ->  s (scrolling)  ->  layout op.
-- Each layout declares its own ops (see hypr/layouts/*); this just composes them
-- into groups, so it never needs touching when a layout gains a new op.
local layout_groups = {}
for _, ls in ipairs(layout_lib.get_submaps()) do
  layout_groups[#layout_groups + 1] = {
    key = ls.key,
    name = "layout-" .. ls.layout,
    desc = ls.layout,
    entries = ls.entries,
  }
end

submap.tree({
  name = "layout",
  desc = "Layout messages",
  entries = layout_groups,
})

local function cycle_workspace_layout()
  local layouts = { "scrolling", "scene" }
  local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
  if not workspace then
    return
  end

  -- tiled_layout reports the compositor's match key ("scene" comes back as
  -- "lua:scene"), so comparisons run against the same normalized form.
  local current = layout_lib.bare_layout(workspace.tiled_layout)
  local next_layout = "scrolling"
  for i = 1, #layouts do
    if layouts[i] == current then
      next_layout = layouts[(i % #layouts) + 1]
      break
    end
  end

  local rule_layout = layout_lib.rule_layout(next_layout)
  if workspace.special then
    hl.workspace_rule({ workspace = tostring(workspace.name), layout = rule_layout })
  else
    hl.workspace_rule({ workspace = tostring(workspace.id), layout = rule_layout })
  end

  -- Cycling back to "scene" needs no manual re-arrange: the compositor calls
  -- the registered layout provider's `recalculate` on every change, scene
  -- layout switch included (see "Hyprland primitives" in AGENTS.md).
end

-- Repeatable on purpose: cycling layouts is a "try it and see" action, and
-- reopening a menu between tries is what made it feel like work.
hyprfocus_binds.bind(config.main_mod .. " + x", cycle_workspace_layout, {
  description = "Cycle the workspace layout",
  submap_universal = true,
})

submap.tree({
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

hyprfocus_binds.bind(
  config.main_mod .. " + " .. config.tertiary_mod .. " + mouse:272",
  hl.dsp.window.drag(),
  { description = "Move a window with left click", submap_universal = true, mouse = true }
)
hyprfocus_binds.bind(config.main_mod .. " + " .. config.tertiary_mod .. " + m", function()
  toggle_minimize:toggle_minimize()
end, { description = "Minimize Window", submap_universal = true })

submap.tree({
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

-- === Which-key (LEO-222 / LEO-327) ===
--
-- SUPER Space is the leader: it opens the which-key overlay listing the
-- named groups. Each entry is an `opens` leaf that nests into the destination
-- submap and stays there, so the overlay re-renders that group's keys in place
-- and escape unwinds exactly one level back to the leader. The group trees
-- below have no direct leader; the only way to reach them is through the hub.
-- The renderer is modules/whichkey in the quickshell repo, fed the tree that
-- hypr/lib/whichkey.lua dumps at config load.
local kb_layouts = { "Dvorak (custom)", "Programmer Dvorak" }
local kb_idx = 1

submap.tree({
  mods = { config.main_mod, "space" },
  name = "which",
  desc = "Which-key",
  entries = {
    {
      key = "t",
      desc = "Terminal",
      opens = "terminal",
      action = function()
        submap.enter("terminal")
      end,
    },
    {
      key = "a",
      desc = "Applications",
      opens = "applications",
      action = function()
        submap.enter("applications")
      end,
    },
    {
      key = "p",
      desc = "Projects",
      opens = "project",
      action = function()
        submap.enter("project")
      end,
    },
    {
      key = "c",
      desc = "Configuration",
      opens = "configuration",
      action = function()
        submap.enter("configuration")
      end,
    },
    {
      key = "m",
      desc = "Layout",
      opens = "layout",
      action = function()
        submap.enter("layout")
      end,
    },
    {
      key = "r",
      desc = "Window management",
      opens = "window-management",
      action = function()
        submap.enter("window-management")
      end,
    },
    {
      key = "s",
      desc = "Screen capture",
      opens = "screencapture",
      action = function()
        submap.enter("screencapture")
      end,
    },
    {
      key = "q",
      desc = "Shell / Quickshell",
      opens = "shell",
      action = function()
        submap.enter("shell")
      end,
    },
    {
      key = "w",
      desc = "Shelves",
      opens = "shelf",
      action = function()
        submap.enter("shelf")
      end,
    },
    {
      key = "d",
      desc = "Dofus",
      opens = "dofus",
      action = function()
        submap.enter("dofus")
      end,
    },
    {
      key = "k",
      desc = "Toggle keyboard layout",
      stay = true,
      action = function()
        hl.dispatch(hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))
        kb_idx = kb_idx % #kb_layouts + 1
        notify:notify("Keyboard layout: " .. kb_layouts[kb_idx], 2000, notify.level.INFO)
      end,
    },
  },
})

bind.exec("p", "hyprpicker -a -n", {
  no_main = true,
  mods = { config.tertiary_mod },
  description = "Execute hyprpicker to extract hex code",
})

bind.exec("comma", "qs -c quantumfate ipc call control toggle", {
  description = "Control centre (theme, wallpaper, sound, focus)",
  submap_universal = true,
})

bind.exec("w", "qs -c quantumfate ipc call workspaceSwitcher toggle", {
  description = "Pick a workspace",
  mods = { config.main_mod, config.secondary_mod },
})

bind.exec("slash", "qs -c quantumfate ipc call cheatsheet toggle", {
  description = "Show keybind cheatsheet",
  submap_universal = true,
})

-- Quickshell control: which-key menu exposing the rest of the shell's IPC
-- surface (theme, cheatsheet, system center). Scene-specific actions live in
-- their own trees; the Dofus tree carries team panel, roster, and store reload.
-- `theme set <palette>` is covered here by `cycle`.
-- Modes (SUPER+f): entering one is a single action that drives both halves of
-- the desk — this runtime's workspaces and binding trees, and the command
-- line's background work.
--
-- The entries are built from the declaration rather than listed here, so
-- adding a mode to the store puts it on the key tree without touching this
-- file. Keys are the first free letter of the mode's id, which keeps them
-- predictable without a second table to maintain.
local hyprfocus = require("hypr.hyprfocus")

local function mode_entries()
  local declaration = hyprfocus.declaration()
  if not declaration then
    -- A desk with no declaration yet. Saying so beats an empty submap that
    -- looks like the feature is broken rather than unseeded.
    return {
      {
        key = "s",
        desc = "No declaration — run ,hyprfocus seed",
        action = function()
          notify:notify("hyprfocus: no declaration; run ,hyprfocus seed", 5000, notify.level.WARNING)
        end,
      },
    }
  end

  local ids = {}
  for id, spec in pairs(declaration.modes or {}) do
    -- Hidden modes (neutral) are the fallback, reached by the way-out bind
    -- below, never offered as a peer.
    if not spec.hidden then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)

  local entries, taken = {}, {}
  for _, id in ipairs(ids) do
    local key
    for i = 1, #id do
      local candidate = id:sub(i, i)
      if candidate:match("%a") and not taken[candidate] then
        key, taken[candidate] = candidate, true
        break
      end
    end
    if key then
      local spec = declaration.modes[id]
      entries[#entries + 1] = {
        key = key,
        desc = "Enter " .. (spec.name or id),
        action = function()
          local _, err = hyprfocus.enter(id)
          if err then
            notify:notify("hyprfocus: " .. err, 5000, notify.level.ERROR)
          end
        end,
      }
    end
  end
  return entries
end

-- The way out, at root and with no submap in front of it.
--
-- A mode withholds things, so the failure that matters is a desk you cannot
-- get back from: if the keys that would undo it are among the ones it took,
-- the only exit is a reboot. This bind is not in any tree, so nothing can
-- withhold it, and it goes straight to the resting mode rather than opening a
-- picker that might itself be gone.
--
-- Deliberately awkward to press. It is an escape hatch, not a shortcut.
hyprfocus_binds.bind(
  -- The key goes inside the modifier list, not appended after it: that is how
  -- every named key in this config is bound (see submap.lua's escape binds).
  -- Appending produced "+SUPER+CTRL+SHIFT+, escape", which Hyprland rejects as
  -- an unknown key — and a bind that fails to create takes the config down.
  bind.parse_mods({ config.main_mod, config.primary_mod, config.secondary_mod, "escape" }),
  function()
    local _, err = hyprfocus.enter("neutral")
    if err then
      notify:notify("hyprfocus: " .. err, 5000, notify.level.ERROR)
    end
  end,
  { description = "Modes: return to neutral", submap_universal = true }
)

submap.tree({
  mods = { config.main_mod, "f" },
  name = "modes",
  desc = "Modes",
  entries = mode_entries(),
})

submap.tree({
  name = "shell",
  desc = "Shell / Quickshell",
  entries = {
    -- The on-demand System Center (LEO-226): settings/actions live in the
    -- widget, which-key carries the door.
    {
      key = "u",
      desc = "Open the System Center",
      action = function()
        qs.call("systemcenter", "toggle")
      end,
    },
    {
      key = "c",
      desc = "Open the Control Centre",
      action = function()
        qs.call("control", "toggle")
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
    -- Wallpaper cycling (LEO-366): every known monitor steps together through
    -- the active palette's shuffled set. `,wallpaper.sh` is the thin wrapper
    -- over `,theme.sh wallpaper next|prev`.
    {
      key = "n",
      desc = "Next wallpaper",
      stay = true,
      action = hl.dsp.exec_cmd(",wallpaper.sh next"),
    },
    {
      key = "p",
      desc = "Previous wallpaper",
      stay = true,
      action = hl.dsp.exec_cmd(",wallpaper.sh prev"),
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
      key = "x",
      desc = "Diagnose window placement",
      action = function()
        diag.run()
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
    {
      key = "f",
      name = "focus",
      desc = "Focus mode",
      entries = {
        -- Open-ended work mood (Focus.qml `set work 0`). The explicit "stop"
        -- bind below is the deliberate way out — firm semantics, no silent
        -- timeout. The mood centre is the primary picker; this is the
        -- keyboard's quick entry into the work mood.
        -- Both go through hyprfocus.enter, not the shell. Setting the
        -- pointer alone leaves the compositor's half unapplied, so the desk
        -- would describe a mode it is not actually in.
        {
          key = "f",
          desc = "Start work",
          action = function()
            local _, err = hyprfocus.enter("work")
            if err then
              notify:notify("hyprfocus: " .. err, 5000, notify.level.ERROR)
            end
          end,
        },
        {
          key = "s",
          desc = "Back to neutral",
          action = function()
            local _, err = hyprfocus.enter("neutral")
            if err then
              notify:notify("hyprfocus: " .. err, 5000, notify.level.ERROR)
            end
          end,
        },
        {
          key = "i",
          desc = "Focus mode status",
          action = function()
            qs.notify("Focus mode", "focus", "status")
          end,
        },
      },
    },
  },
})
