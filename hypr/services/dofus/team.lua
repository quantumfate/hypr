local common = require("hypr.services.dofus.common")
local qs = require("hypr.lib.qs")

local DOFUS_CLASS = "Dofus.x64"
local DOUBLE_CLICK_TAG = "dofus-double-click"

local M = {}

---Open the Quickshell rename widget for the focused window. The pid is captured
---now (while the window is focused) and passed to the widget, which then grabs
---keyboard focus itself — so the correct window is renamed.
function M.rename_prompt()
  local active = hl.get_active_window()
  if active then
    qs.call("window", "prompt", tostring(active.pid))
  end
end

---Active window is a Dofus client?
---@return boolean
local function on_dofus()
  local active = hl.get_active_window()
  return active ~= nil and active.class == DOFUS_CLASS
end

---Map of currently existing Dofus window titles, plus the focused window.
---@return table<string, boolean> existing, HL.Window? current
local function dofus_windows()
  local windows = hl.get_windows({ class = DOFUS_CLASS })
  if #windows == 0 then
    return {}, nil
  end
  -- Currently focused Dofus window = lowest focus_history_id
  local current = windows[1]
  local existing = {}
  for _, w in ipairs(windows) do
    existing[w.title] = true
    if w.focus_history_id < current.focus_history_id then
      current = w
    end
  end
  return existing, current
end

---Team character names -> existing window titles, kept in turn order.
---@param team string[]
---@param existing table<string, boolean>
---@return string[]
local function existing_titles(team, existing)
  local titles = {}
  for _, name in ipairs(team) do
    local title = common.title_prefix .. name
    if existing[title] then
      titles[#titles + 1] = title
    end
  end
  return titles
end

---Focus next/prev Dofus window in turn order, wrapping around.
---Delegates the whole name<->window<->focus join to the Quickshell UI, which
---maintains it live (DofusWindows service); the compositor no longer queries
---clients here. `team` is unused (the UI owns team order) but kept for the
---shared call sites. Guarded so it only acts while a Dofus window is focused.
---@param team string[] unused (UI-owned turn order); kept for call compat
---@param reversed boolean true = previous, false = next
function M.iterate(team, reversed)
  if not on_dofus() then
    return
  end
  qs.call("dofusWindows", reversed and "prev" or "next")
end

---Focus a single team member by 1-based turn index and raise it. Delegates to
---the UI join (0-based there); guarded to only act while on a Dofus window.
---@param team string[] unused (UI-owned turn order); kept for call compat
---@param i integer 1-based position in the team
function M.activate(team, i)
  if not on_dofus() then
    return
  end
  qs.call("dofusWindows", "activate", tostring(i - 1))
end

---@param title string
---@return string hyprctl eval to focus a window by title and raise it
local function focus_eval(title)
  return ("hyprctl -q eval 'hl.dispatch(hl.dsp.focus({ window = [[title:%s]] })) hl.dispatch(hl.dsp.window.bring_to_top())'"):format(
    title
  )
end

---Visit each existing team window, left-click at the cursor's current position,
---then return focus to `main`. Click timing needs sleeps, so the sequence runs
---in a detached shell rather than blocking the compositor thread.
---@param team string[] character names
---@param main string? character to focus when done (default: last in team)
function M.press(team, main)
  if not on_dofus() then
    return
  end

  main = main or team[#team]

  local existing = dofus_windows()
  local titles = existing_titles(team, existing)
  if #titles == 0 then
    return
  end

  local lines = {
    "hyprctl -q eval 'hl.config({ animations = { enabled = false } })'",
    'eval "$(xdotool getmouselocation --shell)"',
  }
  for _, title in ipairs(titles) do
    lines[#lines + 1] = focus_eval(title)
    lines[#lines + 1] = "sleep 0.25"
    lines[#lines + 1] = 'xdotool mousemove "$X" "$Y"'
    lines[#lines + 1] = "xdotool click 1"
  end
  lines[#lines + 1] = focus_eval(common.title_prefix .. main)
  lines[#lines + 1] = "hyprctl -q eval 'hl.config({ animations = { enabled = true } })'"

  hl.exec_cmd(table.concat(lines, "\n"))
end

---Start a detached auto-clicker: double left-click every 0.2s until stopped.
function M.double_click_start()
  hl.exec_cmd("( while true; do xdotool click --repeat 2 --delay 50 1; sleep 0.2; done ) # " .. DOUBLE_CLICK_TAG)
end

---Stop the auto-clicker started by double_click_start.
function M.double_click_stop()
  hl.exec_cmd("pkill -f " .. DOUBLE_CLICK_TAG)
end

return M
