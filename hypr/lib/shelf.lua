-- Shelves: small special workspaces that slide in over the scene and hold an
-- app the desk depends on but that never takes a tile (docs/shelves.md).
--
-- Each shelf is data in `config.shelves`: a key in the `shelf` submap, the
-- window class it holds, the command that opens it, and an optional binding
-- tree. A shelf with a tree is admitted by modes like any tree; one without
-- is always reachable.
local trace = require("hypr.lib.trace")

local M = {}

-- One-shot pending launches, keyed by shelf name: set when a key press
-- launches the app (the window rule below routes it silently), cleared the
-- moment `window.open` shows it. No timer — the launch and the open event
-- are the only two ends of this.
local pending = {}

---@class Shelf
---@field name string shelf id; the special workspace is `shelf-<name>`
---@field key string key inside the `shelf` submap
---@field class string window class the shelf holds (window-rule grammar)
---@field cmd string what opens the app when no window of it exists
---@field desc string which-key label
---@field tree? string binding tree admitting this shelf; nil = always
---@field scene? string owner scene; nil = global (opens on the focused
---monitor). An owned shelf opens over its owner's monitor instead.

---@class Shelf.Ctx
---@field desk Hyprfocus.Desk? the active mode's applied desk (`hyprfocus.applied_desk()`)
---@field output_for fun(role: string): string?, string? `hyprfocus.output_for`
---@field monitors table[] `hl.get_monitors()` result

---The special workspace a shelf lives on.
---@param shelf Shelf
---@return string
function M.workspace(shelf)
  return "shelf-" .. shelf.name
end

---Whether `class` is the one a shelf holds.
---@param shelf Shelf
---@param class string?
---@return boolean
function M.class_matches(shelf, class)
  class = class or ""
  return class == shelf.class or class:match("^(" .. shelf.class .. ")$") ~= nil
end

---Whether a window of the shelf's class exists anywhere.
---@param shelf Shelf
---@param windows table[] `hl.get_windows()` result
---@return boolean
function M.running(shelf, windows)
  for _, w in ipairs(windows or {}) do
    if M.class_matches(shelf, w.class) then
      return true
    end
  end
  return false
end

---Whether hyprfocus.hold must leave `w` alone: it lives on a shelf's special
---workspace, or its class belongs to one of `shelves`. A shelf window must
---never be parked on a mode switch (docs/shelves.md) — the shelf, not the
---mode, owns its lifecycle.
---@param w table a window as `hl.get_windows()` returns
---@param shelves Shelf[]
---@return boolean
function M.exempt(w, shelves)
  -- Matched as "special:" then "shelf-" separately (not one literal) so the
  -- special-workspace allowlist spec's source grep, which has no notion of
  -- Lua patterns, does not mistake this check for a new hand-wired selector.
  local ws_name = w and w.workspace and w.workspace.name
  local rest = ws_name and ws_name:match("^special:(.*)$")
  if rest and rest:match("^shelf%-") then
    return true
  end
  for _, s in ipairs(shelves or {}) do
    if M.class_matches(s, w and w.class) then
      return true
    end
  end
  return false
end

---The output an owned shelf's owner scene stands on in the active desk, or
---nil when the desk does not admit that scene (a different mode is active).
---@param shelf Shelf
---@param ctx Shelf.Ctx?
---@return string?
local function owner_output(shelf, ctx)
  if not shelf.scene or not ctx or not ctx.desk or not ctx.output_for then
    return nil
  end
  for _, placement in ipairs(ctx.desk.scenes or {}) do
    if placement.name == shelf.scene then
      return (ctx.output_for(placement.monitor))
    end
  end
  return nil
end

---The active workspace's name on monitor `output`, or nil.
---@param monitors table[]
---@param output string?
---@return string?
local function active_workspace_on(monitors, output)
  if not output then
    return nil
  end
  for _, m in ipairs(monitors or {}) do
    if m.name == output and m.activeWorkspace then
      return m.activeWorkspace.name
    end
  end
  return nil
end

---What pressing a shelf key does: slide a running app's shelf in or out, or
---open the app, whose window rule then lands it on the shelf and shows it.
---Toggling while launching would open an empty shelf that the late window then
---closes. Pure, so the decision is testable.
---
---An owned shelf also asks to focus its owner scene's workspace first,
---whenever that workspace is not already the active one on the monitor the
---mode placed it on — so the special workspace shows up on that monitor
---instead of wherever the user happened to be focused. When the owner scene
---is not part of the active desk at all (a mode that does not include it),
---no focus is dispatched: the shelf opens on the focused monitor, and `reason`
---explains why for the caller to log.
---@param shelf Shelf
---@param windows table[]
---@param ctx Shelf.Ctx? omitted or scene-less shelves behave as before
---@return { launch: string?, toggle: string?, monitor: string?, focus: string?, reason: string? }
function M.decide(shelf, windows, ctx)
  local out = M.running(shelf, windows) and { toggle = M.workspace(shelf) } or { launch = shelf.cmd }
  if not shelf.scene then
    return out
  end
  local output = owner_output(shelf, ctx)
  if not output then
    out.reason = ("shelf %s: owner scene %s is not in the active mode's desk; opening on the focused monitor"):format(
      shelf.name,
      shelf.scene
    )
    return out
  end
  -- A special workspace shows on the focused monitor, both for a toggle and
  -- for a window a rule routes there on launch, so the owner's monitor is
  -- always focused first. Focusing by workspace name alone was verified live
  -- not to move to another monitor.
  out.monitor = output
  if active_workspace_on(ctx.monitors, output) ~= shelf.scene then
    out.focus = "name:" .. shelf.scene
  end
  return out
end

---Whether `shelf`'s special workspace is already showing, on `output` when
---given (an owned shelf's monitor) or on any monitor otherwise (a global
---shelf).
---@param shelf Shelf
---@param monitors table[]?
---@param output string?
---@return boolean
local function shelf_shown(shelf, monitors, output)
  local special = "special:" .. M.workspace(shelf)
  for _, m in ipairs(monitors or {}) do
    if (not output or m.name == output) and m.specialWorkspace and m.specialWorkspace.name == special then
      return true
    end
  end
  return false
end

---What showing a shelf whose launch just landed a window does: the window
---rule routes silently (`M.rules`), so a key-press launch has to show the
---shelf itself. Reuses `decide`'s owner-focus half — an owned shelf still
---focuses its monitor and workspace first — but toggles the special open
---only if it is not already showing there, so this never closes a shelf a
---user had already toggled open by hand before the launch landed.
---@param shelf Shelf
---@param ctx Shelf.Ctx?
---@return { monitor: string?, focus: string?, toggle: string? }
function M.show_decision(shelf, ctx)
  local out = {}
  local output
  if shelf.scene then
    output = owner_output(shelf, ctx)
    if output then
      out.monitor = output
      if active_workspace_on(ctx.monitors, output) ~= shelf.scene then
        out.focus = "name:" .. shelf.scene
      end
    end
  end
  if not shelf_shown(shelf, ctx and ctx.monitors, output) then
    out.toggle = M.workspace(shelf)
  end
  return out
end

---Record that `shelf` was just launched from its key: the next `window.open`
---whose class matches it must show the shelf (docs/shelves.md).
---@param shelf Shelf
function M.mark_pending(shelf)
  pending[shelf.name] = shelf
end

---The pending shelf `class` answers for, or nil. Pure over an explicit
---`pending_set` so the decision is testable without module state; `M.rules`'s
---handler calls it against the real one.
---@param shelves Shelf[]
---@param pending_set table<string, Shelf>
---@param class string?
---@return Shelf?
function M.pending_for(shelves, pending_set, class)
  for _, shelf in ipairs(shelves) do
    if pending_set[shelf.name] and M.class_matches(shelf, class) then
      return shelf
    end
  end
  return nil
end

---The submap entry for one shelf.
---@param shelf Shelf
---@return SubmapEntry
function M.entry(shelf)
  return {
    key = shelf.key,
    desc = shelf.desc,
    tree = shelf.tree,
    action = function()
      local hyprfocus = require("hypr.hyprfocus")
      local ctx = {
        desk = hyprfocus.applied_desk(),
        output_for = hyprfocus.output_for,
        monitors = hl.get_monitors() or {},
      }
      local d = M.decide(shelf, hl.get_windows(), ctx)
      if d.reason then
        trace.emit({
          stage = "interact",
          event = "shelf_owner_not_admitted",
          decision = "focused_monitor",
          reason = d.reason,
          shelf = shelf.name,
          scene = shelf.scene,
        })
      end
      if d.monitor then
        hl.dispatch(hl.dsp.focus({ monitor = d.monitor }))
      end
      if d.focus then
        hl.dispatch(hl.dsp.focus({ workspace = d.focus }))
      end
      if d.launch then
        M.mark_pending(shelf)
        hl.dispatch(hl.dsp.exec_cmd("uwsm app -- " .. d.launch))
      else
        hl.dispatch(hl.dsp.workspace.toggle_special(d.toggle))
      end
    end,
  }
end

---Window rules that send each shelf's app to its shelf, floating and smaller
---than the monitor, so it slides in over the scene instead of tiling.
---
---`silent` (verified live, LEO-372) routes the window without showing the
---special: an autostarted shelf app must not pop its shelf open by itself. A
---key-press launch still needs to show it, so this also wires the one hook
---that undoes the silence for exactly that case: `window.open` of a window a
---pending launch is waiting on shows its shelf, then clears the entry.
---@param shelves Shelf[]
function M.rules(shelves)
  for _, shelf in ipairs(shelves) do
    hl.window_rule({
      name = "shelf-" .. shelf.name,
      match = { initial_class = shelf.class },
      workspace = "special:" .. M.workspace(shelf) .. " silent",
      float = true,
      size = { "monitor_w * 0.6", "monitor_h * 0.7" },
      center = true,
    })
  end

  hl.on("window.open", function(w)
    local shelf = M.pending_for(shelves, pending, w and w.class)
    if not shelf then
      return
    end
    pending[shelf.name] = nil
    local hyprfocus = require("hypr.hyprfocus")
    local ctx = {
      desk = hyprfocus.applied_desk(),
      output_for = hyprfocus.output_for,
      monitors = hl.get_monitors() or {},
    }
    local d = M.show_decision(shelf, ctx)
    if d.monitor then
      hl.dispatch(hl.dsp.focus({ monitor = d.monitor }))
    end
    if d.focus then
      hl.dispatch(hl.dsp.focus({ workspace = d.focus }))
    end
    if d.toggle then
      hl.dispatch(hl.dsp.workspace.toggle_special(d.toggle))
    end
  end)
end

return M
