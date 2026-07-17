-- Passive peek cheatsheet.
--
-- Separate from the main cheatsheet (SUPER+/ or the shell submap), which is a
-- focus-grabbing, dimmed, centered modal. This one is hands-off: when you enter
-- a submap and *dwell* there past a delay, a non-interactive contextual panel
-- fades in so you can read the binds while still seeing (and using) the window
-- underneath.
--
-- All the "what submap am I in" logic comes from the Hyprland event system via
-- hypr/lib/hypr.lua rather than any state we track ourselves — the trigger is
-- clear by design. Rendering (non-focusable layer surface) is quickshell-side:
-- CheatSheetPeek.qml, IPC target `cheatsheetPeek`.
--
-- Lifecycle: the panel opens once, after you first dwell in a submap past
-- `config.peek_delay_ms`, then *stays* open while you traverse nested submaps
-- (re-reading the new context live). It tears down when either
--   * you land back at root (a leaf action exits the tree, or you escape out), or
--   * you stop navigating and the auto-fade elapses (cheatsheet_peek_ms from the
--     theme store, so it is tunable live). Each navigation restarts that timer,
--     so moving between submaps never fades mid-read.
local hypr = require("hypr.lib.hypr")
local qs = require("hypr.lib.qs")
local Store = require("hypr.lib.store")

local theme = Store.define("theme")

-- Pending dwell timer (before the first show); nil once fired or cancelled.
---@type HL.Timer|nil
local pending = nil
-- Auto-fade timer (hide after dwelling); restarted on each navigation.
---@type HL.Timer|nil
local fade = nil
-- Whether the panel is currently open, so navigation neither re-arms the dwell
-- timer nor re-opens what is already there.
local shown = false

---@return integer ms auto-fade timeout, configurable via the theme store.
local function fade_ms()
  return theme:get("cheatsheet_peek_ms") or 6000
end

local function cancel_pending()
  if pending then
    pending:set_enabled(false)
    pending = nil
  end
end

local function cancel_fade()
  if fade then
    fade:set_enabled(false)
    fade = nil
  end
end

---Close the peek (if open) and clear all timers/state.
local function close()
  cancel_pending()
  cancel_fade()
  if shown then
    qs.call("cheatsheetPeek", "close")
    shown = false
  end
end

---(Re)start the auto-fade countdown.
local function arm_fade()
  cancel_fade()
  fade = hypr.oneshot(fade_ms(), function()
    fade = nil
    if shown then
      qs.call("cheatsheetPeek", "close")
      shown = false
    end
  end)
end

hypr.on_submap_change(function(submap)
  -- Hyprland reports root as "" (raw event) or "reset" (the dispatcher keyword
  -- we use). Reaching root is the hard close.
  if submap == "" or submap == "reset" then
    close()
    return
  end

  if shown then
    -- Navigating within the tree: keep it up, restart the fade countdown so
    -- it only fades once you settle.
    arm_fade()
  elseif not pending then
    -- First dwell into the tree: show after the delay, then start fading.
    pending = hypr.oneshot(config.peek_delay_ms, function()
      pending = nil
      shown = true
      qs.call("cheatsheetPeek", "open")
      arm_fade()
    end)
  end
end)
