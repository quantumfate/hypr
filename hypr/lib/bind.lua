local M = {}

---@param mods string[]?
function M.parse_mods(mods)
  return mods and "+" .. table.concat(mods, "+") .. "+" or "+"
end

---Binds workspace focus and window move actions
function M.bind_workspaces()
  local host = config.host
  for i, key in ipairs(host.workspaces.workspace_keys) do
    if host.workspaces.workspace_specs[i] then
      M.focus_workspace(key, tostring(i))
      M.move_focused_to_workspace(key, tostring(i), { "SHIFT" })
    end
  end
end

--- TODO: indicisive about workspace names/digits
--- TODO: the variable order of the call is wrong and doesn't work as intended
--- TODO: it kind of works by accident because it always returns a number
---
---@param workspace string
---@return string, string?
local function get_workspace_direction(workspace)
  return workspace:match("%d") and workspace,
    workspace or function()
      if workspace == "e-1" then
        return "previous", workspace
      elseif workspace == "e+1" then
        return "next", workspace
      else
        return workspace, ("name:%s"):format(workspace)
      end
    end
end

---@param key string
---@param workspace string workspace name unless it's a single diget or a "e+" selector
---@param mods string[]?
function M.move_focused_to_workspace(key, workspace, mods)
  local direction, ws_selector = get_workspace_direction(workspace)
  hl.bind(
    config.main_mod .. M.parse_mods(mods) .. key,
    hl.dsp.window.move({ workspace = ws_selector, follow = true }),
    {
      description = ("Workspace: Move focused to %s"):format(direction),
    }
  )
end

---@param key string
---@param workspace string workspace name unless it's a single diget or a "e+" selector
---@param mods string[]?
function M.focus_workspace(key, workspace, mods)
  local direction, ws_selector = get_workspace_direction(workspace)
  hl.bind(
    config.main_mod .. M.parse_mods(mods) .. key,
    hl.dispatch(function()
      if hl.get_active_workspace() and hl.get_active_workspace().special then
        hl.dsp.workspace.toggle_special()
      end
      return hl.dsp.focus({ workspace = ws_selector })
    end),
    { description = ("Workspace: Focus %s"):format(direction) }
  )
end

---Bind a key to a layout-aware action. The active workspace's `tiled_layout`
---is resolved at press time and the handler registered for it (in
---hypr/layouts/*) runs. See hypr/lib/layout.lua.
---@param mods string[]?
---@param action string action name, e.g. "focus_left" | "swap_right"
---@param description string
function M.layout_action(mods, action, description)
  hl.bind(M.parse_mods(mods), function()
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
  hl.bind(prefix .. key, action, {
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
  hl.bind(
    "XF86MonBrightness" .. direction,
    hl.dsp.exec_cmd(cmd),
    { locked = true, repeating = true, description = "Brightness " .. direction:lower() }
  )
end

---@param key string XF86Audio suffix (e.g. "RaiseVolume", "Mute") — "XF86Audio" auto-prepended unless key already starts with "XF86"
---@param cmd string shell command to execute
---@param description string
---@param mods string[]?
---@param repeating boolean?
---@param callback function?
function M.audio(key, cmd, description, mods, repeating, callback)
  local full_key = key:find("XF86") and key or ("XF86Audio" .. key)
  local prefix = mods and (table.concat(mods, "+") .. "+") or ""
  hl.bind(prefix .. full_key, function()
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
---@param app string app command
---@param description string
---@param mods string[]?
---@return SubmapEntry
function M.app_entry(key, app, description, mods)
  return { key = key, mods = mods, desc = description, action = hl.dsp.exec_cmd("uwsm app -- " .. app) }
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

---Toggle a special workspace.
---@param key string
---@param name string special workspace name
---@return SubmapEntry
function M.special_ws_entry(key, name)
  return { key = key, desc = "Toggle special workspace " .. name, action = hl.dsp.workspace.toggle_special(name) }
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
