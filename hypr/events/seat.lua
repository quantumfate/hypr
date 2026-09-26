-- The seat: which monitor the user is on. There is exactly one, it is the
-- KEYBOARD's monitor, and this module owns it. Every consumer -- workspace
-- keys, `mod+h/l`, the widgets quickshell opens -- reads it from here (or from
-- the `geometry` store's `seat` key, which this publishes), never from the
-- compositor's focused-monitor mark or the pointer.
--
-- Why not the mark. `hl.get_active_monitor()`, `monitors[].focused` and the
-- `monitor.focused` event all follow the POINTER on this desk:
-- `misc.mouse_move_focuses_monitor` moves the mark whenever the pointer enters
-- another output, while `input.follow_mouse = 0` leaves the keyboard where it
-- was. Spiked nested (2026-09-26): keyboard crossed onto an empty monitor, then
-- the pointer moved on the monitor it left -- the mark and `monitor.focused`
-- went back with the pointer, no `window.active` fired, the keyboard stayed.
-- That is the "stale mark" and the "stale seat" earlier fixes chased: both were
-- the pointer.
--
-- So the seat moves on exactly three things:
--
--   * `window.active` with a window: the keyboard went there, by key or click;
--   * `workspace.active`: a workspace switch, which the pointer never causes;
--   * `M.claim(monitor)`: every hypr action that moves the keyboard somewhere a
--     window may not take it (a cross onto an empty monitor, a switch to an
--     empty workspace) says so up front, because the compositor may emit
--     nothing when it has nowhere to put the keyboard.
--
-- When the seat changes monitor and the pointer is not on it, the pointer is
-- warped to the seat monitor's centre, so the two can only diverge by the
-- user moving the mouse -- and even then the seat does not follow until they
-- click or type somewhere. `cursor.no_warps` stays on for everything else.
local nav = require("hypr.lib.nav")
local Store = require("hypr.lib.store")

local M = {}

local geometry_store = Store.define("geometry")

---@type string? the monitor the keyboard is on
local monitor_name = nil

---The live monitor named `name`, or nil.
---@param name string?
---@return table?
local function monitor_by_name(name)
  if not name then
    return nil
  end
  local ok, monitors = pcall(hl.get_monitors)
  for _, m in ipairs(ok and monitors or {}) do
    if m.name == name then
      return m
    end
  end
  return nil
end

---Bring the pointer onto the seat's monitor, unless it is already there.
---@param name string
local function warp_pointer_to(name)
  local ok, monitors = pcall(hl.get_monitors)
  monitors = ok and monitors or {}
  local cok, cursor = pcall(hl.get_cursor_pos)
  local under = cok and cursor and nav.monitor_at(monitors, cursor.x, cursor.y) or nil
  if under == name then
    return
  end
  local centre = nav.monitor_centre(monitors, name)
  if centre then
    pcall(function()
      hl.dispatch(hl.dsp.cursor.move({ x = centre.x, y = centre.y }))
    end)
  end
end

---Publish the seat for quickshell. Only on change: the store write bumps a
---file watch on the other side.
---@param name string
local function publish(name)
  pcall(function()
    local current = geometry_store:get("seat")
    if not (type(current) == "table" and current.monitor == name) then
      geometry_store:set({ seat = { monitor = name } })
    end
  end)
end

---Publish which workspace each monitor shows (`geometry.shown`,
---`{ <monitor>: <workspace> }`), for the bar's workspace row. Quickshell cannot
---answer this itself on this build -- a workspace's `monitor` comes back
---unresolved there -- and every workspace switch passes through here anyway,
---with the workspace's own monitor. Written only when the map changed.
---@param monitor string
---@param workspace string
local function publish_shown(monitor, workspace)
  pcall(function()
    local shown = geometry_store:get("shown")
    shown = type(shown) == "table" and shown or {}
    if shown[monitor] == workspace then
      return
    end
    shown[monitor] = workspace
    geometry_store:set({ shown = shown })
  end)
end

---Move the seat. A change of monitor publishes, and brings the pointer along
---a tick later -- after the focus dispatch that usually follows a claim, so
---the compositor's own focus lands before the pointer moves.
---@param name string?
local function move_to(name)
  if not name or name == monitor_name then
    return
  end
  monitor_name = name
  publish(name)
  require("hypr.lib.hypr").oneshot(1, function()
    if monitor_name == name then
      warp_pointer_to(name)
    end
  end)
end

hl.on("window.active", function(window)
  local monitor = window and window.monitor
  if monitor and monitor.name then
    move_to(monitor.name)
  end
end)

-- The workspace's own monitor, not a lookup by name: two monitors can show
-- workspaces with the same name (a placeholder `1` beside a declared one).
hl.on("workspace.active", function(workspace)
  local monitor = workspace and workspace.monitor
  local name = type(monitor) == "string" and monitor or (monitor and monitor.name)
  if name then
    publish_shown(name, workspace.name)
    move_to(name)
  end
end)

---The monitor the keyboard is on.
---@return string?
function M.monitor()
  return monitor_name
end

---The live monitor object the keyboard is on, from `hl.get_monitors()` (the
---one that carries its active workspace).
---@return table?
function M.monitor_object()
  return monitor_by_name(monitor_name)
end

---The workspace showing on the seat's monitor.
---@return string?
function M.workspace()
  local m = monitor_by_name(monitor_name)
  return m and nav.monitor_workspace(m) or nil
end

---Claim the seat ahead of the event that confirms it. Every hypr action that
---moves the keyboard calls this before its dispatch.
---@param name string?
function M.claim(name)
  move_to(name)
end

-- The first answer, before any event: the active window's monitor, else the
-- compositor's mark. This is the only place the mark is read, and only because
-- at config load nothing else has spoken yet -- the pointer and the keyboard
-- have not had a chance to part.
do
  local ok, w = pcall(hl.get_active_window)
  local from_window = ok and w and w.monitor and w.monitor.name
  local mok, marked = pcall(hl.get_active_monitor)
  monitor_name = from_window or (mok and marked and marked.name) or nil
  if monitor_name then
    publish(monitor_name)
  end
  local mons_ok, monitors = pcall(hl.get_monitors)
  for _, m in ipairs(mons_ok and monitors or {}) do
    local ws = nav.monitor_workspace(m)
    if m.name and ws then
      publish_shown(m.name, ws)
    end
  end
end

return M
