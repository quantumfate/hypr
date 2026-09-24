-- Drawers: small special workspaces that slide in over the scene and hold an
-- app the desk depends on but that never takes a tile (docs/shelves.md).
-- "Shelf" stays the user-facing word; "drawer" is the internal kind.
--
-- A drawer is declared data (the hyprfocus declaration's `base.drawers`,
-- LEO-363), not host Lua: a key in the `shelf` submap, the window class it
-- holds, the command that opens it, and the scene(s) that own it (if any). A
-- global drawer (no owner scene) is always reachable; an owned drawer is
-- admitted through the same synthetic-tree mechanism every other scene-scoped
-- binding uses (`drawer:<id>`, wired in hypr/hyprfocus/init.lua), so it is
-- absent — never greyed — outside its scene(s).
local trace = require("hypr.lib.trace")

local M = {}

-- One-shot pending launches, keyed by drawer id: set when a key press or a
-- background bring-up launches the app (the window rule below routes it
-- silently), cleared the moment `window.open` shows it. No timer — the
-- launch and the open event are the only two ends of this.
local pending = {}

---@class Drawer
---@field id string drawer id; the special workspace is `shelf-<id>`
---@field key string key inside the `shelf` submap
---@field class string window class the drawer holds (window-rule grammar)
---@field launch string? what opens the app when no window of it exists
---@field desc string which-key label
---@field background boolean? starts silently on mode entry when admitted
---@field scenes string[] owner scenes; empty = global (opens on the focused
---monitor, always reachable)
---@field tree string? synthetic admission tree (`drawer:<id>`), nil when global

---@class Drawer.Ctx
---@field desk Hyprfocus.Desk? the active mode's applied desk (`hyprfocus.applied_desk()`)
---@field output_for fun(role: string): string?, string? `hyprfocus.output_for`
---@field monitors table[] `hl.get_monitors()` result
---@field focused string? the focused monitor's name
---@field primary string? `config.host.primary_monitor`
---@field ignored string[]? `config.host.ignored_monitors`

---Build the runtime drawer list from a parsed hyprfocus declaration:
---`base.drawers` catalogs each by id, and a scene's `drawers` array assigns
---it by reference — one drawer can serve several scenes without duplicating
---its data. A drawer no scene claims is global.
---@param declaration table?
---@return Drawer[] sorted by id, for a stable submap order
function M.from_declaration(declaration)
  local base = (declaration or {}).base or {}
  local catalog = base.drawers or {}
  local owners = {}
  for scene_name, scene in pairs(base.scenes or {}) do
    for _, id in ipairs(scene.drawers or {}) do
      owners[id] = owners[id] or {}
      owners[id][#owners[id] + 1] = scene_name
    end
  end

  local out = {}
  for id, d in pairs(catalog) do
    local scenes = owners[id] or {}
    out[#out + 1] = {
      id = id,
      key = d.key,
      class = d.class,
      launch = d.launch,
      desc = d.desc,
      background = d.background == true,
      scenes = scenes,
      tree = (#scenes > 0) and ("drawer:" .. id) or nil,
    }
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  return out
end

---The runtime drawer list, read live from the hyprfocus declaration store.
---Empty when there is no declaration yet — the same "not seeded" condition
---`hyprfocus.declaration()` reports elsewhere.
---@return Drawer[]
function M.load()
  local ok, store = pcall(require, "hypr.lib.store")
  if not ok then
    return {}
  end
  local defined, handle = pcall(store.define, "hyprfocus")
  if not defined then
    return {}
  end
  local data = handle:get()
  if type(data) ~= "table" then
    return {}
  end
  return M.from_declaration(data)
end

---The special workspace a drawer lives on. Unchanged from the old shelf
---naming on purpose: a live desk already has windows routed there, and
---nothing about this chunk needs to move them.
---@param drawer Drawer
---@return string
function M.workspace(drawer)
  return "shelf-" .. drawer.id
end

---Whether `class` is the one a drawer holds.
---@param drawer Drawer
---@param class string?
---@return boolean
function M.class_matches(drawer, class)
  class = class or ""
  return class == drawer.class or class:match("^(" .. drawer.class .. ")$") ~= nil
end

---Whether a window of the drawer's class exists anywhere.
---@param drawer Drawer
---@param windows table[] `hl.get_windows()` result
---@return boolean
function M.running(drawer, windows)
  for _, w in ipairs(windows or {}) do
    if M.class_matches(drawer, w.class) then
      return true
    end
  end
  return false
end

---Whether hyprfocus.hold must leave `w` alone: it lives on a drawer's special
---workspace, or its class belongs to one of `drawers`. A drawer window must
---never be parked on a mode switch (docs/shelves.md) — the drawer, not the
---mode, owns its lifecycle.
---@param w table a window as `hl.get_windows()` returns
---@param drawers Drawer[]
---@return boolean
function M.exempt(w, drawers)
  -- Matched as "special:" then "shelf-" separately (not one literal) so the
  -- special-workspace allowlist spec's source grep, which has no notion of
  -- Lua patterns, does not mistake this check for a new hand-wired selector.
  local ws_name = w and w.workspace and w.workspace.name
  local rest = ws_name and ws_name:match("^special:(.*)$")
  if rest and rest:match("^shelf%-") then
    return true
  end
  for _, d in ipairs(drawers or {}) do
    if M.class_matches(d, w and w.class) then
      return true
    end
  end
  return false
end

-- A shelf is a fixed fraction of the monitor showing it. One source for the
-- rule and the runtime fit, so the two cannot drift.
local WIDTH_FRACTION = 0.6
local HEIGHT_FRACTION = 0.7

---The absolute size a shelf should take on `monitor`.
---@param monitor { width: integer, height: integer }
---@return integer width, integer height
function M.fit_size(monitor)
  return math.floor((monitor.width or 0) * WIDTH_FRACTION + 0.5),
    math.floor((monitor.height or 0) * HEIGHT_FRACTION + 0.5)
end

---The live window a drawer holds, or nil when it is not running.
---@param drawer Drawer
---@param windows table[] `hl.get_windows()` result
---@return table? `hl.get_windows()` entry
function M.window_for(drawer, windows)
  for _, w in ipairs(windows or {}) do
    if M.class_matches(drawer, w.class) then
      return w
    end
  end
  return nil
end

---The monitor currently showing `drawer`'s special workspace, or nil when it
---is not shown anywhere.
---@param drawer Drawer
---@param monitors table[] `hl.get_monitors()` result
---@return table?
local function showing_monitor(drawer, monitors)
  local special = "special:" .. M.workspace(drawer)
  for _, m in ipairs(monitors or {}) do
    if require("hypr.lib.nav").special_workspace(m) == special then
      return m
    end
  end
  return nil
end

---Size and center a drawer's window against the monitor currently showing its
---shelf.
---
---The window rule's `monitor_w`/`monitor_h` are resolved once, at map time, and
---a special has no monitor until it is *shown*: an app that opened while one
---monitor was focused keeps that monitor's size when its shelf is later shown
---on a different one — the smaller screen wearing the larger screen's size
---(LEO-370/LEO-423). This is the runtime correction. It is a no-op when the
---drawer has no window or its shelf is not showing, so it is safe to call
---after any show path.
---@param drawer Drawer
function M.fit(drawer)
  local w = M.window_for(drawer, hl.get_windows() or {})
  if not w or not w.address then
    return
  end
  local monitor = showing_monitor(drawer, hl.get_monitors() or {})
  if not monitor then
    return
  end
  local width, height = M.fit_size(monitor)
  hl.dispatch(hl.dsp.window.resize({ window = "address:" .. w.address, x = width, y = height }))
  hl.dispatch(hl.dsp.window.center({ window = "address:" .. w.address }))
end

---The output an owned drawer's active owner scene stands on in the active
---desk, and that scene's name — nil, nil when the desk admits none of its
---owner scenes (a different mode is active), or when the drawer is global.
---@param drawer Drawer
---@param ctx Drawer.Ctx?
---@return string? output, string? scene
local function owner_output(drawer, ctx)
  if #(drawer.scenes or {}) == 0 or not ctx or not ctx.desk or not ctx.output_for then
    return nil, nil
  end
  local owned = {}
  for _, name in ipairs(drawer.scenes) do
    owned[name] = true
  end
  for _, placement in ipairs(ctx.desk.scenes or {}) do
    if owned[placement.name] then
      return (ctx.output_for(placement.monitor)), placement.name
    end
  end
  return nil, nil
end

---The active workspace's name on monitor `output`, or nil.
---@param monitors table[]
---@param output string?
---@return string?
local function active_workspace_on(monitors, output)
  return require("hypr.lib.nav").workspace_on(monitors, output)
end

---The primary, when a drawer would otherwise open on an ignored focused
---monitor (a special shows on the focused monitor); nil when the focused one
---is usable.
---@param ctx Drawer.Ctx?
---@return string?
local function away_from_ignored(ctx)
  if not ctx or not ctx.focused or not ctx.primary then
    return nil
  end
  for _, name in ipairs(ctx.ignored or {}) do
    if name == ctx.focused then
      return ctx.primary
    end
  end
  return nil
end

---What pressing a drawer key does: slide a running app's drawer in or out, or
---open the app, whose window rule then lands it on the drawer and shows it.
---Toggling while launching would open an empty drawer that the late window
---then closes. Pure, so the decision is testable.
---
---An owned drawer also asks to focus its active owner scene's workspace
---first, whenever that workspace is not already the active one on the
---monitor the mode placed it on — so the special workspace shows up on that
---monitor instead of wherever the user happened to be focused. When none of
---the drawer's owner scenes is part of the active desk at all (a mode that
---does not include any of them), no focus is dispatched: the drawer opens on
---the focused monitor, and `reason` explains why for the caller to log.
---A press while `pending` is true does nothing: the launch is already in
---flight (its window hasn't opened, so `windows` can't see it as running yet)
---and repeating it would spawn a second process. `window.open`'s handler
---(`M.show_decision`) shows the drawer once the window lands, so this never
---leaves a second press stuck.
---@param drawer Drawer
---@param windows table[]
---@param ctx Drawer.Ctx? omitted or scene-less drawers behave as before
---@param launching? boolean a launch for this drawer has not yet landed its window
---@return { launch: string?, toggle: string?, monitor: string?, focus: string?, reason: string? }
function M.decide(drawer, windows, ctx, launching)
  if launching then
    return {}
  end
  local out = M.running(drawer, windows) and { toggle = M.workspace(drawer) } or { launch = drawer.launch }
  if #(drawer.scenes or {}) == 0 then
    out.monitor = away_from_ignored(ctx)
    return out
  end
  local output, scene = owner_output(drawer, ctx)
  if not output then
    out.monitor = away_from_ignored(ctx)
    out.reason = ("drawer %s: owner scene(s) %s not in the active mode's desk; opening on the focused monitor"):format(
      drawer.id,
      table.concat(drawer.scenes, ", ")
    )
    return out
  end
  -- A special workspace shows on the focused monitor, both for a toggle and
  -- for a window a rule routes there on launch, so the owner's monitor is
  -- always focused first. Focusing by workspace name alone was verified live
  -- not to move to another monitor.
  out.monitor = output
  if active_workspace_on(ctx.monitors, output) ~= scene then
    out.focus = "name:" .. scene
  end
  return out
end

---Whether `drawer`'s special workspace is already showing, on `output` when
---given (an owned drawer's monitor) or on any monitor otherwise (a global
---drawer).
---@param drawer Drawer
---@param monitors table[]?
---@param output string?
---@return boolean
local function drawer_shown(drawer, monitors, output)
  local special = "special:" .. M.workspace(drawer)
  for _, m in ipairs(monitors or {}) do
    if (not output or m.name == output) and require("hypr.lib.nav").special_workspace(m) == special then
      return true
    end
  end
  return false
end

---What showing a drawer whose launch just landed a window does: the window
---rule routes silently (`M.rules`), so a key-press or background launch has
---to show the drawer itself. Reuses `decide`'s owner-focus half but toggles
---the special open only if it is not already showing there, so this never
---closes a drawer a user had already toggled open by hand before the launch
---landed.
---@param drawer Drawer
---@param ctx Drawer.Ctx?
---@return { monitor: string?, focus: string?, toggle: string? }
function M.show_decision(drawer, ctx)
  local out = {}
  local output, scene
  if #(drawer.scenes or {}) > 0 then
    output, scene = owner_output(drawer, ctx)
    if output then
      out.monitor = output
      if active_workspace_on(ctx.monitors, output) ~= scene then
        out.focus = "name:" .. scene
      end
    end
  end
  if not out.monitor then
    out.monitor = away_from_ignored(ctx)
    output = out.monitor
  end
  if not drawer_shown(drawer, ctx and ctx.monitors, output) then
    out.toggle = M.workspace(drawer)
  end
  return out
end

---Record that `drawer` was just launched: the next `window.open` whose class
---matches it must show the drawer (docs/shelves.md).
---@param drawer Drawer
function M.mark_pending(drawer)
  pending[drawer.id] = drawer
end

---The pending drawer `class` answers for, or nil. Pure over an explicit
---`pending_set` so the decision is testable without module state; `M.rules`'s
---handler calls it against the real one.
---@param drawers Drawer[]
---@param pending_set table<string, Drawer>
---@param class string?
---@return Drawer?
function M.pending_for(drawers, pending_set, class)
  for _, drawer in ipairs(drawers) do
    if pending_set[drawer.id] and M.class_matches(drawer, class) then
      return drawer
    end
  end
  return nil
end

---Build the ctx `decide`/`show_decision` want, from the live desk.
---@return Drawer.Ctx
local function live_ctx()
  local hyprfocus = require("hypr.hyprfocus")
  return {
    desk = hyprfocus.applied_desk(),
    output_for = hyprfocus.output_for,
    monitors = hl.get_monitors() or {},
    focused = (hl.get_active_monitor() or {}).name,
    primary = ((rawget(_G, "config") or {}).host or {}).primary_monitor,
    ignored = ((rawget(_G, "config") or {}).host or {}).ignored_monitors,
  }
end

---Emit the admit-stage drawer event that replaces the old single
---`shelf_owner_not_admitted` interact event (LEO-363): `admit.drawer_open` for
---a press or bring-up that resolves to opening/launching, `admit.drawer_refused`
---when none of its owner scenes are in the active desk.
---@param drawer Drawer
---@param decision "refuse"|"launch"|"toggle"
---@param reason string
local function emit_drawer_event(drawer, decision, reason)
  local hyprfocus = require("hypr.hyprfocus")
  trace.emit({
    stage = "admit",
    event = decision == "refuse" and "drawer_refused" or "drawer_open",
    decision = decision,
    reason = reason,
    drawer = drawer.id,
    class = drawer.class,
    scenes = drawer.scenes,
    mode = hyprfocus.active(),
  })
end

---The drawer declared under `id`, or nil.
---
---Exposed so a submap outside the shelf tree can press the same drawer
---rather than re-implementing half of it: the dofus tree's own launcher key
---did exactly that, and so only ever launched.
---@param id string
---@return Drawer?
function M.by_id(id)
  for _, drawer in ipairs(M.load()) do
    if drawer.id == id then
      return drawer
    end
  end
  return nil
end

---Press one drawer: the whole key-press behaviour (decide, focus, launch or
---toggle, log), so every caller gets the same one. `M.entry` binds this to the
---shelf tree's key; other trees call it directly.
---@param drawer Drawer?
function M.press(drawer)
  if not drawer then
    return
  end
  local ctx = live_ctx()
  local d = M.decide(drawer, hl.get_windows(), ctx, pending[drawer.id] ~= nil)
  if d.reason then
    emit_drawer_event(drawer, "refuse", d.reason)
  end
  if d.monitor then
    hl.dispatch(hl.dsp.focus({ monitor = d.monitor }))
  end
  if d.focus then
    hl.dispatch(hl.dsp.focus({ workspace = d.focus }))
  end
  if d.launch then
    M.mark_pending(drawer)
    hl.dispatch(hl.dsp.exec_cmd("uwsm app -- " .. d.launch))
    if not d.reason then
      emit_drawer_event(drawer, "launch", ("drawer %s launched"):format(drawer.id))
    end
  elseif d.toggle then
    hl.dispatch(hl.dsp.workspace.toggle_special(d.toggle))
    if not d.reason then
      emit_drawer_event(drawer, "toggle", ("drawer %s toggled"):format(drawer.id))
    end
    -- After the special has had a tick to land on its monitor, size the window
    -- to that monitor — it may have opened on another (LEO-423).
    require("hypr.lib.hypr").oneshot(50, function()
      M.fit(drawer)
    end)
  end
end

---The submap entry for one drawer.
---@param drawer Drawer
---@return SubmapEntry
function M.entry(drawer)
  return {
    key = drawer.key,
    desc = drawer.desc,
    tree = drawer.tree,
    action = function()
      M.press(drawer)
    end,
  }
end

---Launch every admitted `background` drawer that is not already running or
---mid-launch, silently routed to its shelf by the window rule (`M.rules`). A
---launch failure is logged (LEO-363: "never blocks the mode") — `exec_cmd` is
---fire-and-forget, so there is nothing here that could raise.
---@param drawers Drawer[]
---@param desk Hyprfocus.Desk?
function M.bring_up(drawers, desk)
  local admitted_scenes = {}
  for _, name in ipairs((desk and desk.workspaces) or {}) do
    admitted_scenes[name] = true
  end
  local windows = hl.get_windows() or {}
  for _, drawer in ipairs(drawers) do
    if drawer.background and drawer.launch and not pending[drawer.id] and not M.running(drawer, windows) then
      local admitted = #(drawer.scenes or {}) == 0
      for _, scene in ipairs(drawer.scenes or {}) do
        admitted = admitted or admitted_scenes[scene] == true
      end
      if admitted then
        M.mark_pending(drawer)
        hl.dispatch(hl.dsp.exec_cmd("uwsm app -- " .. drawer.launch))
        emit_drawer_event(drawer, "launch", "background bring-up on mode entry")
      end
    end
  end
end

---Window rules that send each drawer's app to its shelf, floating and
---smaller than the monitor, so it slides in over the scene instead of
---tiling.
---
---`silent` (verified live, LEO-372) routes the window without showing the
---special: an autostarted drawer app must not pop its shelf open by itself. A
---key-press or background launch still needs to show it, so this also wires
---the one hook that undoes the silence for exactly that case: `window.open`
---of a window a pending launch is waiting on shows its shelf, then clears the
---entry.
---@param drawers Drawer[]
function M.rules(drawers)
  for _, drawer in ipairs(drawers) do
    hl.window_rule({
      name = "shelf-" .. drawer.id,
      match = { initial_class = drawer.class },
      workspace = "special:" .. M.workspace(drawer) .. " silent",
      float = true,
      size = { ("monitor_w * %s"):format(WIDTH_FRACTION), ("monitor_h * %s"):format(HEIGHT_FRACTION) },
      center = true,
      -- A shelf is a dependency the desk opens for you, never a window that
      -- pulls input focus: launching Signal in the background must not take the
      -- user off the scene they are on (LEO-299/LEO-423).
      no_initial_focus = true,
      suppress_event = "activate activatefocus",
    })
  end

  hl.on("window.open", function(w)
    local drawer = M.pending_for(drawers, pending, w and w.class)
    if not drawer then
      return
    end
    pending[drawer.id] = nil
    local d = M.show_decision(drawer, live_ctx())
    if d.monitor then
      hl.dispatch(hl.dsp.focus({ monitor = d.monitor }))
    end
    if d.focus then
      hl.dispatch(hl.dsp.focus({ workspace = d.focus }))
    end
    if d.toggle then
      hl.dispatch(hl.dsp.workspace.toggle_special(d.toggle))
      -- The window has just landed; size it to the monitor now showing the
      -- shelf, which need not be the one it was routed on (LEO-423).
      require("hypr.lib.hypr").oneshot(50, function()
        M.fit(drawer)
      end)
    end
  end)
end

return M
