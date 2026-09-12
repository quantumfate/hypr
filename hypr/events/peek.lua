-- Passive peek cheatsheet.
--
-- Timing follows which-key's contract: appear once you dwell in a submap, stay
-- for as long as that context holds, leave shortly after you do. There is
-- deliberately no timer that hides the panel while you are still navigating —
-- the thing you are reading must not disappear mid-decision.

local hypr = require("hypr.lib.hypr")
local qs = require("hypr.lib.qs")
local Store = require("hypr.lib.store")

local theme = Store.define("theme")

-- Pending dwell timer (before the first show); nil once fired or cancelled.
---@type HL.Timer|nil
local pending = nil
-- Linger timer armed on leaving the tree; cancelled if a submap is re-entered
-- inside the window, so submap → root → submap does not flicker.
---@type HL.Timer|nil
local linger = nil
-- Whether the panel is currently open, so navigation neither re-arms the dwell
-- timer nor re-opens what is already there.
local shown = false

---@return integer ms grace period after leaving the tree, via the theme store.
local function linger_ms()
  return theme:get("cheatsheet_linger_ms") or 400
end

local function cancel_pending()
  if pending then
    pending:set_enabled(false)
    pending = nil
  end
end

local function cancel_linger()
  if linger then
    linger:set_enabled(false)
    linger = nil
  end
end

---Close the peek (if open) and clear all timers/state.
local function close()
  cancel_pending()
  cancel_linger()
  if shown then
    qs.call("cheatsheetPeek", "close")
    shown = false
  end
end

hypr.on_submap_change(function(submap)
  -- Hyprland reports root as "" (raw event) or "reset" (the dispatcher keyword
  -- we use). Leaving the tree closes the panel, but only after a grace period:
  -- a submap that resets and immediately re-enters should not blink.
  if submap == "" or submap == "reset" then
    cancel_pending()
    if shown and not linger then
      linger = hypr.oneshot(linger_ms(), function()
        linger = nil
        close()
      end)
    end
    return
  end

  -- Back inside the tree before the grace period elapsed: keep what is on screen.
  cancel_linger()

  if shown or pending then
    -- Navigating within the tree. The panel follows along on the Quickshell
    -- side; nothing here should touch its lifetime.
    return
  end

  -- First dwell into the tree: show after the delay, then leave it up.
  pending = hypr.oneshot(config.peek_delay_ms, function()
    pending = nil
    shown = true
    qs.call("cheatsheetPeek", "open")
  end)
end)
