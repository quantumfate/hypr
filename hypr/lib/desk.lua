-- The monitor-scoped workspace switch: the one way a workspace key, `mod+Tab`,
-- a bar dot or the workspace switcher changes what a monitor shows.
--
-- A switch names the monitor it is FOR and only ever changes that monitor, to
-- a scene the active mode places there. Focusing a named workspace outright
-- follows the workspace to whichever monitor it happens to stand on and takes
-- the keyboard with it -- spiked nested (2026-09-26), and `on_current_monitor`
-- is ignored -- so a workspace found elsewhere is moved home first.
--
-- Called from Lua by the binds (`hypr/lib/bind.lua`) and from quickshell
-- through `bin/,desk.sh switch <monitor> <name>`.
local hyprfocus = require("hypr.hyprfocus")
local nav = require("hypr.lib.nav")
local seat = require("hypr.events.seat")

local M = {}

---The active mode's scene names placed on `output`, in desk order.
---@param output string
---@return string[]
function M.scenes_on(output)
  local desk = hyprfocus.applied_desk()
  if not desk then
    return {}
  end
  local placements = {}
  for _, placement in ipairs(desk.scenes or {}) do
    placements[#placements + 1] = { name = placement.name, output = hyprfocus.output_for(placement.monitor) }
  end
  return nav.workspaces_on_monitor(placements, output)
end

---The monitor the live workspace `name` stands on, or nil when it does not
---exist yet.
---@param name string
---@return string?
local function standing_on(name)
  for _, ws in ipairs(hl.get_workspaces() or {}) do
    if ws.name == name then
      local m = ws.monitor
      return type(m) == "string" and m or (m and m.name) or nil
    end
  end
  return nil
end

---Put workspace `name` on `output` if it stands anywhere else. Returns false
---when the mode does not place `name` on `output` -- the switch is refused.
---@param output string
---@param name string
---@return boolean
function M.home(output, name)
  local admitted = false
  for _, candidate in ipairs(M.scenes_on(output)) do
    if candidate == name then
      admitted = true
    end
  end
  if not admitted then
    return false
  end
  local at = standing_on(name)
  if at and at ~= output then
    hl.dispatch(hl.dsp.workspace.move({ workspace = "name:" .. name, monitor = output }))
  end
  return true
end

---Show scene `name` on `output` and put the keyboard there. A special shown
---over that monitor is closed first. Returns false when refused.
---@param output string
---@param name string
---@return boolean
function M.switch(output, name)
  if not (output and name) or not M.home(output, name) then
    return false
  end
  local monitor
  for _, m in ipairs(hl.get_monitors() or {}) do
    if m.name == output then
      monitor = m
    end
  end
  local shown = monitor and nav.special_workspace(monitor)
  seat.claim(output)
  -- Focus the monitor first, so a workspace that does not exist yet is
  -- created on it rather than on whichever monitor the compositor marks.
  hl.dispatch(hl.dsp.focus({ monitor = output }))
  if shown then
    hl.dispatch(hl.dsp.workspace.toggle_special(shown:match("^special:(.*)$") or shown))
  end
  hl.dispatch(hl.dsp.focus({ workspace = "name:" .. name }))
  return true
end

---Move the focused window to scene `name` on `output`, following it. Returns
---false when refused.
---@param output string
---@param name string
---@return boolean
function M.send(output, name)
  if not (output and name) or not M.home(output, name) then
    return false
  end
  seat.claim(output)
  hl.dispatch(hl.dsp.window.move({ workspace = "name:" .. name, follow = true }))
  return true
end

return M
