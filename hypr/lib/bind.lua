local hyprfocus_binds = require("hypr.hyprfocus.binds")
local nav = require("hypr.lib.nav")
local hyprfocus = require("hypr.hyprfocus")
local M = {}

---@param mods string[]?
function M.parse_mods(mods)
  return mods and "+" .. table.concat(mods, "+") .. "+" or "+"
end

---The active mode's scene names placed on one monitor output, in desk order
---(`hypr/hyprfocus/init.lua` `applied_desk`/`output_for`; see docs/scenes.md
---"Scene sets: mode → scene → monitor"). Resolved at press time, not at
---config load, since it depends on the mode and which monitor is focused —
---both of which change without a reload.
---@param monitor_output string
---@return string[]
local function scenes_on_monitor(monitor_output)
  local desk = hyprfocus.applied_desk()
  if not desk then
    return {}
  end
  local placements = {}
  for _, placement in ipairs(desk.scenes or {}) do
    placements[#placements + 1] = { name = placement.name, output = hyprfocus.output_for(placement.monitor) }
  end
  return nav.workspaces_on_monitor(placements, monitor_output)
end

---Workspace row (LEO-344 decision): `mod+<key>` focuses, `mod+shift+<key>`
---moves the focused window to, the Nth scene of the active mode's scene list
---on the FOCUSED monitor — position N is this key's index in
---`workspace_keys`, never a hardcoded digit. A monitor with fewer scenes than
---a key's position makes that key a no-op, by construction: `nth_workspace`
---returns nil and the handler dispatches nothing.
---
---Registered once per `workspace_keys` entry regardless of what any given
---mode/monitor holds — which-key renders "Workspace <symbol> on this
---monitor" generically rather than a description that would have to know the
---mode and focused monitor ahead of press time (AGENTS.md's "never show a
---binding that cannot execute" is satisfied by the description being true in
---general, not by hiding positions a monitor happens not to fill right now).
function M.bind_workspace_row()
  for i, key in ipairs(config.host.workspaces.workspace_keys) do
    local symbol = nav.symbol_for(key)
    hyprfocus_binds.bind(config.main_mod .. M.parse_mods() .. key, function()
      local monitor = hl.get_active_monitor()
      local name = monitor and nav.nth_workspace(scenes_on_monitor(monitor.name), i)
      if not name then
        return
      end
      hl.dispatch(function()
        if hl.get_active_workspace() and hl.get_active_workspace().special then
          hl.dsp.workspace.toggle_special()
        end
        return hl.dsp.focus({ workspace = "name:" .. name })
      end)
    end, { description = ("Workspace %s on this monitor"):format(symbol) })

    hyprfocus_binds.bind(config.main_mod .. M.parse_mods({ "SHIFT" }) .. key, function()
      local monitor = hl.get_active_monitor()
      local name = monitor and nav.nth_workspace(scenes_on_monitor(monitor.name), i)
      if not name then
        return
      end
      hl.dispatch(hl.dsp.window.move({ workspace = "name:" .. name, follow = true }))
    end, { description = ("Move focused window to workspace %s on this monitor"):format(symbol) })
  end
end

---@param key string
---@param selector string the workspace selector the dispatcher speaks, e.g. "name:code"
---@param label string how the bind's description spells the workspace
---@param mods string[]?
function M.move_focused_to_workspace(key, selector, mods, label)
  hyprfocus_binds.bind(
    config.main_mod .. M.parse_mods(mods) .. key,
    hl.dsp.window.move({ workspace = selector, follow = true }),
    {
      description = ("Workspace: Move focused to %s"):format(label),
    }
  )
end

---@param key string
---@param selector string the workspace selector the dispatcher speaks, e.g. "name:code"
---@param label string how the bind's description spells the workspace
---@param mods string[]?
function M.focus_workspace(key, selector, label, mods)
  hyprfocus_binds.bind(
    config.main_mod .. M.parse_mods(mods) .. key,
    hl.dispatch(function()
      if hl.get_active_workspace() and hl.get_active_workspace().special then
        hl.dsp.workspace.toggle_special()
      end
      return hl.dsp.focus({ workspace = selector })
    end),
    { description = ("Workspace: Focus %s"):format(label) }
  )
end

---Bind a key to a layout-aware action. The active workspace's `tiled_layout`
---is resolved at press time and the handler registered for it (in
---hypr/layouts/*) runs. See hypr/lib/layout.lua.
---@param mods string[]?
---@param action string action name, e.g. "focus_left" | "swap_right"
---@param description string
function M.layout_action(mods, action, description)
  hyprfocus_binds.bind(M.parse_mods(mods), function()
    require("hypr.lib.layout").dispatch(action)
  end, { description = description, submap_universal = true })
end

---@class ExecOpts
---@field description string?
---@field mods string[]?
---@field no_main boolean? skip main_mod prefix
---@field submap_universal boolean?
---@field locked boolean?
---@field repeating boolean?
---@field mouse boolean?

---Generic binding. Defaults: prefix with config.main_mod, no submap_universal/locked/repeating.
---`cmd` may be:
---  - a string: wrapped in hl.dsp.exec_cmd
---  - a HL.Dispatcher (e.g. hl.dsp.*): bound directly
---  - a function: bound as the keypress callback. Call hl.dispatch(...) inside it
---    (any number of times) to run dispatchers wrapped by Hyprland's bind rules.
---@param key string
---@param cmd string|HL.Dispatcher|function
---@param opts ExecOpts?
function M.exec(key, cmd, opts)
  opts = opts or {}
  local prefix
  if opts.no_main then
    prefix = opts.mods and (table.concat(opts.mods, "+") .. "+") or ""
  else
    prefix = config.main_mod .. M.parse_mods(opts.mods)
  end
  local action = type(cmd) == "string" and hl.dsp.exec_cmd(cmd) or cmd
  ---@cast action HL.Dispatcher|function
  hyprfocus_binds.bind(prefix .. key, action, {
    description = opts.description,
    submap_universal = opts.submap_universal,
    locked = opts.locked,
    repeating = opts.repeating,
    mouse = opts.mouse,
  })
end

---@param direction "Up"|"Down"
---@param cmd string shell command
function M.brightness(direction, cmd)
  hyprfocus_binds.bind(
    "XF86MonBrightness" .. direction,
    hl.dsp.exec_cmd(cmd),
    { locked = true, repeating = true, description = "Brightness " .. direction:lower() }
  )
end

---@param key string XF86Audio suffix (e.g. "RaiseVolume", "Mute") — "XF86Audio" auto-prepended
---unless key already starts with "XF86"
---@param cmd string shell command to execute
---@param description string
---@param mods string[]?
---@param repeating boolean?
---@param callback function?
function M.audio(key, cmd, description, mods, repeating, callback)
  local full_key = key:find("XF86") and key or ("XF86Audio" .. key)
  local prefix = mods and (table.concat(mods, "+") .. "+") or ""
  hyprfocus_binds.bind(prefix .. full_key, function()
    hl.dispatch(hl.dsp.exec_cmd(cmd))
    if callback then
      callback()
    end
  end, { locked = true, repeating = repeating, description = description })
end

-- === Submap entry factories ===
-- Each returns a SubmapEntry (see hypr/lib/submap.lua) for use in submap.tree,
-- so submaps have a single, declarative construction path.

---Launch an app via uwsm. Closes the submap on use (which-key style).
---@param key string
---@param app AppScope entry from config.apps
---@param description string
---@param mods string[]?
---@return SubmapEntry
function M.app_entry(key, app, description, mods)
  return { key = key, mods = mods, desc = description, action = hl.dsp.exec_cmd("uwsm app -- " .. app.cmd) }
end

---Take a screenshot via hyprshot.
---@param key string
---@param mode "window"|"output"|"region"
---@param description string
---@return SubmapEntry
function M.screenshot_entry(key, mode, description)
  return { key = key, desc = description, action = hl.dsp.exec_cmd(",hyprshot.sh --" .. mode) }
end

---Toggle recclip. Same bind starts and stops (recclip detects a running
---recorder via its pidfile); `mode`/`audio` only affect the START invocation.
---@param key string
---@param mode "region"|"output"
---@param audio boolean
---@param description string
---@return SubmapEntry
function M.screenrecord_entry(key, mode, audio, description)
  local flags = ({ region = "", output = "-o" })[mode] or ""
  local cmd = (",recclip.sh " .. flags):gsub("%s+$", "")
  if audio then
    cmd = cmd .. " -a"
  end
  return { key = key, desc = description, action = hl.dsp.exec_cmd(cmd) }
end

---Open a project through `,proj.sh`: rofi picker, then that project's tmux
---session on `window` — focusing the window the project already has, or
---spawning one. The script spawns its own uwsm scope, so this must not go
---through bind.app_entry (which would nest uwsm scopes).
---@param key string
---@param window string? template window name ("nvim" | "zsh" | "run"); nil uses
---the project's own first template window
---@param description string
---@param mods string[]?
---@param new boolean? always spawn a second window instead of focusing the
---project's existing one
---@param here boolean? re-point the focused window at the project instead of
---opening another one — its tmux client is swapped for the other server's
---@return SubmapEntry
function M.project_entry(key, window, description, mods, new, here)
  local flags = (new and "-n " or "") .. (here and "--here " or "")
  local cmd = ",proj.sh " .. flags .. "pick" .. (window and (" " .. window) or "")
  return { key = key, mods = mods, desc = description, action = hl.dsp.exec_cmd(cmd) }
end

---Relative split resize. Stays in the submap and repeats so a hold resizes
---continuously. Exactly one of x/y should be non-zero.
---@param key string
---@param x integer
---@param y integer
---@param mods string[]?
---@return SubmapEntry
function M.resize_entry(key, x, y, mods)
  local step = x ~= 0 and x or y
  local axis = x ~= 0 and "vertically" or "horizontally"
  return {
    key = key,
    mods = mods,
    stay = true,
    repeating = true,
    desc = ("Resize %s by %s"):format(axis, step),
    action = hl.dsp.window.resize({ x = x, y = y, relative = true }),
  }
end

return M
