-- Passive peek cheatsheet.

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
