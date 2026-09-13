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

---The Dofus group, read off any live client. windowrules.lua groups every
---Dofus.x64 window ("set always"), so any member's `.group` reaches the same
---HL.Group. nil while no Dofus client is open.
---@return HL.Group?
local function dofus_group()
  local windows = hl.get_windows({ class = DOFUS_CLASS })
  if #windows == 0 then
    return nil
  end
  return windows[1].group
end

---HL.Group.members is a bare HL.Window when the group holds exactly one,
---otherwise an array — normalize to an array.
---@param group HL.Group
---@return HL.Window[]
local function group_members(group)
  local members = group.members
  if members == nil then
    return {}
  end
  if members.title then
    return { members }
  end
  return members
end

---Map of currently existing Dofus window titles, read off the group's
---membership rather than a standalone window-list scan.
---@return table<string, boolean>
local function dofus_windows()
  local group = dofus_group()
  if not group then
    return {}
  end
  local existing = {}
  for _, w in ipairs(group_members(group)) do
    existing[w.title] = true
  end
  return existing
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

---Focus next/prev group member, wrapping — a native group-tab cycle
---(hl.dsp.group.next/prev) now that the Dofus clients are one Hyprland group,
---rather than a Quickshell-mediated window join. `team` is unused (the group
---itself is the roster) but kept for the shared call sites. Guarded so it only
---acts while a Dofus window is focused.
---@param _team string[] unused (the group is the roster); kept for call compat
---@param reversed boolean true = previous, false = next
function M.iterate(_team, reversed)
  if not on_dofus() then
    return
  end
  hl.dispatch(reversed and hl.dsp.group.prev() or hl.dsp.group.next())
end

---Overload for MOD+H / MOD+L: while on a Dofus window, walk the group
---left/right (same native cycle as `iterate`). Returns true when it handled
---the key, so the caller can fall back to normal focus-move.
---@param reversed boolean true = left/prev, false = right/next
---@return boolean handled
function M.nav(reversed)
  if not on_dofus() then
    return false
  end
  hl.dispatch(reversed and hl.dsp.group.prev() or hl.dsp.group.next())
  return true
end

---Focus the 1-based Nth PRESENT (alive) team member and raise it. Mapping is
---dense over open windows only: with 2 windows open, F1/F2 hit them regardless
---of their raw team position. Reads the live group directly (dofus_windows())
---instead of asking a Quickshell join; guarded to only act while on a Dofus
---window.
---@param team string[] turn order (character names)
---@param i integer 1-based position among present members
function M.activate(team, i)
  if not on_dofus() then
    return
  end
  local title = existing_titles(team, dofus_windows())[i]
  if not title then
    return
  end
  hl.dispatch(hl.dsp.focus({ window = "title:" .. title }))
end

---@param title string
---@return string hyprctl eval to focus a window by title and raise it
local function focus_eval(title)
  local eval = "hyprctl -q eval 'hl.dispatch(hl.dsp.focus({ window = [[title:%s]] })) "
    .. "hl.dispatch(hl.dsp.window.bring_to_top())'"
  return eval:format(title)
end

---Visit each existing team window, left-click at the cursor's current position,
---then return focus to `main`, and finally back to whatever was focused before
---this ran (LEO-129) — `prev_dofus_title`, captured below before the iteration
---starts. Click timing needs sleeps, so the sequence runs in a detached shell
---rather than blocking the compositor thread. Titles still address individual
---group members correctly: focusing by title brings that tab forward even
---while it sits in the background of the Dofus group.
---@param team string[] character names
---@param main string? character to focus when done (default: last in team)
function M.press(team, main)
  if not on_dofus() then
    return
  end

  local prev_dofus_title = hl.get_active_window().title

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

  lines[#lines + 1] = focus_eval(prev_dofus_title)
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
