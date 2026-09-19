-- Reload must not move focus (LEO-400).
--
-- Verified live (tests/e2e, `hc reload` with no window event and no code
-- path here dispatching a focus change at all): a plain `hyprctl reload`
-- still leaves each monitor showing a different workspace than it did a
-- moment before. Nothing in this repo's Lua causes it -- `apply_mode` never
-- dispatches focus, and `hypr/scene/provider.lua`'s own `config.reloaded`
-- hook only forces a relayout, restoring the monitor it started from. The
-- yank is the compositor's own reload-time bookkeeping; this module's job is
-- only to put focus back exactly where the user left it, not to explain why
-- it moved.
--
-- Two halves, on purpose:
--   * `M.capture` runs on every real focus change (`workspace.active`,
--     `window.active`) and remembers, per monitor, which workspace (and
--     which window) is showing -- cheap, mtime-cached store writes, the same
--     pattern `hypr/lib/store.lua`'s other consumers already use.
--   * `M.restore`, wired to `config.reloaded`, runs exactly once per reload:
--     it reads back what capture last wrote (from BEFORE the reload landed,
--     since a reload never runs Lua in between) and reissues whatever focus
--     is needed to match it.
--
-- A mode's declared `main` scene (LEO-400; validated in
-- `hypr/hyprfocus/resolve.lua`) is only ever the fallback for a monitor whose
-- captured workspace is no longer in the running mode's admitted set -- never
-- a substitute for a genuine restore, and never invoked on a schedule of its
-- own. The standing rule outranks this feature: a monitor with nothing safe
-- to restore and no `main` to fall back to is left exactly as the compositor
-- put it, not guessed at.
--
-- Registered once per reload from a plain top-level call
-- (`hypr/events/start.lua`), never from inside the one-shot
-- `hl.on("hyprland.start", ...)` handler -- that handler's own registrations
-- (`hypr/hyprfocus/watch.lua`) do not survive a reload (verified live: its
-- event subscriptions never fire again after the first `hyprctl reload`),
-- which this module cannot depend on without the same fate.
local store = require("hypr.lib.store")

local M = {}

local STORE_NAME = "hyprfocus.focus_cache"

---@class Hyprfocus.FocusSnapshot
---@field monitors table<string, string> monitor name -> its active workspace name
---@field focused_workspace string? the globally focused workspace, if any
---@field focused_window string? the globally focused window's address, if any

---Every monitor's active workspace, plus which one actually holds input
---focus, in the shape `M.restore`/`plan_restore` consume. Pure but for the
---read; kept separate from `M.capture` so a test can hand in fixture
---monitors without a compositor.
---@param monitors { name: string, active_workspace: { name: string }? }[]
---@param focused_workspace_name string?
---@param focused_window_address string?
---@return Hyprfocus.FocusSnapshot
function M.build(monitors, focused_workspace_name, focused_window_address)
  local per_monitor = {}
  for _, m in ipairs(monitors or {}) do
    if m.active_workspace and m.active_workspace.name then
      per_monitor[m.name] = m.active_workspace.name
    end
  end
  return {
    monitors = per_monitor,
    focused_workspace = focused_workspace_name,
    focused_window = focused_window_address,
  }
end

---Remember what the desk currently shows. Called on every `workspace.active`
---and `window.active` -- cheap: the store handle only writes when the
---snapshot actually differs in content from what is on disk (`Store.Handle`'s
---own atomic-write-on-change), and reading it back costs nothing until then
---either (mtime-cached).
function M.capture()
  local ok, handle = pcall(store.define, STORE_NAME)
  if not ok then
    return
  end
  local monitors_ok, monitors = pcall(hl.get_monitors)
  local ws_ok, workspace = pcall(hl.get_active_workspace)
  local win_ok, window = pcall(hl.get_active_window)
  local snapshot = M.build(
    monitors_ok and monitors or {},
    ws_ok and workspace and workspace.name or nil,
    win_ok and window and window.address or nil
  )
  pcall(function()
    handle:update(function()
      return snapshot
    end)
  end)
end

---@class Hyprfocus.FocusMove
---@field monitor string
---@field workspace string
---@field reason "restore"|"main_fallback"

---@class Hyprfocus.FocusTarget
---@field workspace string
---@field window string? present only when the captured window should also be
---refocused

---What a reload's restore should dispatch, decided in full and pure so the
---compositor-facing half is a thin executor.
---
---A monitor whose captured workspace still matches what it shows right now
---needs nothing. One that drifted is restored to the captured workspace
---UNLESS `admitted` says it is no longer part of the running mode, in which
---case the mode's own `main` scene stands in for it -- but only on the
---monitor `main` actually places to; a mismatched monitor is left alone
---rather than guessed at (the standing "never jump where the user did not
---direct" rule outranks the fallback).
---
---`admitted == nil` means "no resolved desk to check against" (a reload that
---lands before anything has applied a mode yet): every captured workspace is
---then treated as still valid, since there is nothing to refuse it against.
---@param snapshot Hyprfocus.FocusSnapshot?
---@param live_monitors { name: string, active_workspace: { name: string }? }[]
---@param admitted table<string, true>? workspaces the running desk admits
---@param main string? the running mode's declared main scene, if any
---@param main_monitor string? the live output `main` is placed on
---@return Hyprfocus.FocusMove[] moves
---@return Hyprfocus.FocusTarget? refocus what should hold true input focus
---when the reload is done, nil if the snapshot named nothing to give it
function M.plan_restore(snapshot, live_monitors, admitted, main, main_monitor)
  local moves = {}
  if not snapshot then
    return moves, nil
  end

  local function still_admitted(name)
    return admitted == nil or admitted[name] == true
  end

  for _, m in ipairs(live_monitors or {}) do
    local current = m.active_workspace and m.active_workspace.name
    local wanted = snapshot.monitors and snapshot.monitors[m.name]
    if wanted and wanted ~= current then
      if still_admitted(wanted) then
        moves[#moves + 1] = { monitor = m.name, workspace = wanted, reason = "restore" }
      elseif main and main_monitor == m.name and main ~= current then
        moves[#moves + 1] = { monitor = m.name, workspace = main, reason = "main_fallback" }
      end
      -- Neither restorable nor this monitor's fallback seat: nothing safe to
      -- do, so nothing is queued for it.
    end
  end

  local refocus = nil
  if snapshot.focused_workspace then
    if still_admitted(snapshot.focused_workspace) then
      refocus = { workspace = snapshot.focused_workspace, window = snapshot.focused_window }
    elseif main then
      refocus = { workspace = main }
    end
  end
  return moves, refocus
end

---Whether `address` is still a live window, so a captured focus target is
---not re-issued against a window that closed meanwhile.
---@param address string?
---@return boolean
local function window_alive(address)
  if not address then
    return false
  end
  for _, w in ipairs(hl.get_windows() or {}) do
    if w.address == address then
      return true
    end
  end
  return false
end

---Undo whatever the reload just did to focus. Wired to `config.reloaded`
---(`M.attach`), so it runs once per reload, immediately -- before any window
---event, and so before the user could have redirected focus themselves in
---between.
---@param desk Hyprfocus.Desk? the running mode's resolved desk, if one could
---be resolved this soon after reload (nil is handled: every captured
---workspace is then treated as admitted, since there is nothing to check
---against yet -- see `plan_restore`)
---@param output_for fun(role: string): string? monitor role -> live output
function M.restore(desk, output_for)
  local ok, handle = pcall(store.define, STORE_NAME)
  if not ok then
    return
  end
  local snapshot = handle:get()
  if type(snapshot) ~= "table" then
    return
  end

  local admitted, main, main_monitor
  if desk then
    admitted = {}
    for _, name in ipairs(desk.workspaces or {}) do
      admitted[name] = true
    end
    main = desk.main
    if main then
      for _, placement in ipairs(desk.scenes or {}) do
        if placement.name == main then
          local out_ok, output = pcall(output_for, placement.monitor)
          main_monitor = out_ok and output or nil
          break
        end
      end
    end
  end

  local monitors_ok, monitors = pcall(hl.get_monitors)
  local moves, refocus = M.plan_restore(snapshot, monitors_ok and monitors or {}, admitted, main, main_monitor)

  local trace = require("hypr.lib.trace")

  ---Apply the plan. Run twice on purpose -- see the re-assert below.
  ---@param emit boolean whether to trace; only the first pass reports
  local function apply(emit)
    for _, move in ipairs(moves) do
      hl.dispatch(hl.dsp.focus({ workspace = "name:" .. move.workspace }))
      if emit then
        trace.emit({
          stage = "admit",
          event = "focus_restored",
          decision = move.reason == "restore" and "restore" or "fallback",
          reason = move.reason == "restore" and "reload must not move focus"
            or "previously focused workspace no longer admitted",
          monitor = move.monitor,
          workspace = move.workspace,
        })
      end
    end

    if refocus then
      if refocus.window and window_alive(refocus.window) then
        hl.dispatch(hl.dsp.focus({ window = "address:" .. refocus.window }))
      else
        hl.dispatch(hl.dsp.focus({ workspace = "name:" .. refocus.workspace }))
      end
    end
  end

  apply(true)
  -- Re-assert shortly after. `config.reloaded` fires BEFORE the reload has
  -- finished activating workspaces: re-creating the mode's persistent
  -- workspaces focuses the last one to come up on each output, which put the
  -- primary on `proton` (the last enabled primary spec) however this restore
  -- had just set it. The pass above therefore plans nothing -- at that instant
  -- no monitor has drifted yet -- and the drift lands afterwards, unopposed.
  --
  -- The plan re-applied is deliberately the one computed above, from the
  -- snapshot read before any of that: re-planning here would read whatever the
  -- reload's own workspace change had meanwhile told `M.capture` to write, and
  -- would restore the desk to the very drift this exists to undo.
  require("hypr.lib.hypr").oneshot(150, function()
    apply(false)
  end)
end

---Register the capture/restore hooks. Called as a plain top-level statement
---(`hypr/events/start.lua`), NOT from inside `hl.on("hyprland.start", ...)`:
---that event fires exactly once per compositor process (verified live --
---two `hyprctl reload`s in a row left a marker written from inside it at 1),
---so anything wired only there never runs again after the first reload. This
---file's own top-level statement re-executes on every `require()`, which a
---reload always re-triggers (`docs/live-config.md`), and that is what keeps
---these two hooks alive across every subsequent reload too.
function M.attach()
  hl.on("workspace.active", M.capture)
  hl.on("window.active", M.capture)
  hl.on("config.reloaded", function()
    local hyprfocus = require("hypr.hyprfocus")
    local resolve = require("hypr.hyprfocus.resolve")
    local desk = nil
    local declaration = hyprfocus.declaration()
    if declaration then
      local mode = hyprfocus.active()
      local ok, resolved = pcall(resolve.resolve, declaration, mode)
      if ok then
        desk = resolved
      end
    end
    M.restore(desk, hyprfocus.output_for)
  end)
end

return M
