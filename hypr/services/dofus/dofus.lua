local dofus_launch = require("hypr.services.dofus.launch")
local common = require("hypr.services.dofus.common")
local team = require("hypr.services.dofus.team")
local swap = require("hypr.services.dofus.swap")
local ipc = require("hypr.services.dofus.ipc")
local submap = require("hypr.lib.submap")

local DOFUS_CLASS = "Dofus.x64"

---Active window is a Dofus client?
---@return boolean
local function on_dofus()
  local active = hl.get_active_window()
  return active ~= nil and active.class == DOFUS_CLASS
end

---@class DofusBindOpts
---@field desc string
---@field send_key? string key name to replay on passthrough (default: `key`)
---@field send_mods? string mods to replay on passthrough (default: "")
---@field mouse? boolean
---@field repeating? boolean
---@field release? boolean
---@field transparent? boolean

---Register a base-layer Dofus bind. On a Dofus window it runs `action`; off it,
---the key is forwarded to the focused window so nothing else notices the bind.
---@param key string full bind string (e.g. "F1", "SUPER + F10", "mouse:274")
---@param action function
---@param opts DofusBindOpts
local function dofus_bind(key, action, opts)
  hl.bind(key, function()
    if on_dofus() then
      action()
    else
      hl.dispatch(hl.dsp.send_shortcut({
        mods = opts.send_mods or "",
        key = opts.send_key or key,
        window = "activewindow",
      }))
    end
  end, {
    description = opts.desc,
    mouse = opts.mouse,
    repeating = opts.repeating,
    release = opts.release,
    transparent = opts.transparent,
  })
end

-- F1..F8 → focus team member N (turn order = team.json order).
for i = 1, 8 do
  dofus_bind("F" .. i, function()
    team.activate(common.team(), i)
  end, { desc = "Dofus: activate team member " .. i })
end

-- Turn-order cycling: arrows + spare F23 (a mouse-side button on some setups).
-- `right`/`F23` = next, `left`/SUPER+F23 = previous. Middle mouse is separate
-- below (press-all, not cycle).
dofus_bind("right", function()
  team.iterate(common.team(), false)
end, { desc = "Dofus: next team member" })
dofus_bind("left", function()
  team.iterate(common.team(), true)
end, { desc = "Dofus: previous team member" })
dofus_bind("F23", function()
  team.iterate(common.team(), false)
end, { desc = "Dofus: next team member" })
dofus_bind(config.main_mod .. " + F23", function()
  team.iterate(common.team(), true)
end, { desc = "Dofus: previous team member", send_key = "F23", send_mods = config.main_mod })
-- Plain click bind (not mouse=true → that is bindm/drag, which passes through).
dofus_bind("mouse:274", function()
  team.press(common.team())
end, { desc = "Dofus: press current member (middle click)" })

-- Press the current member (single click at the cursor across the team).
dofus_bind("up", function()
  team.press(common.team())
end, { desc = "Dofus: press current member" })

-- Detached double-click auto-clicker (already modified, so unambiguous).
dofus_bind(config.main_mod .. " + F10", function()
  team.double_click_start()
end, { desc = "Dofus: start double-click", send_key = "F10", send_mods = config.main_mod })
dofus_bind(config.main_mod .. " + F11", function()
  team.double_click_stop()
end, {
  desc = "Dofus: stop double-click",
  send_key = "F11",
  send_mods = config.main_mod,
  release = true,
  transparent = true,
})

-- The Dofus submap now only hosts management actions (launching, renaming, swap
-- toggle, opening the team UI) — nothing you need mid-fight, so no more team
-- submaps and no team selection here (the UI owns that).
submap.tree({
  mods = { config.main_mod, "d" },
  name = "dofus",
  desc = "Dofus",
  sticky = false,
  entries = {
    {
      key = "d",
      desc = "Toggle launch-on-open",
      action = function()
        dofus_launch:toggle_enable()
      end,
    },
    { key = "a", desc = "Launch Ankama launcher", action = hl.dsp.exec_cmd("gamemoderun ankama-launcher") },
    {
      key = "t",
      desc = "Open team selector",
      action = function()
        ipc.team_selector("toggle")
      end,
    },
    {
      key = "n",
      desc = "Rename focused window",
      action = function()
        team.rename_prompt()
      end,
    },
    {
      key = "s",
      desc = "Toggle swap",
      action = function()
        swap.toggle()
      end,
    },
    {
      key = "l",
      desc = "Assign character classes",
      action = function()
        ipc.class_assigner("toggle")
      end,
    },
    {
      key = "c",
      desc = "Show focused window class",
      action = function()
        local active = hl.get_active_window()
        if active and active.class == DOFUS_CLASS then
          -- Window title is `<title_prefix><character name>`; strip the prefix
          -- to recover the name the class map is keyed by.
          local name = active.title:gsub("^" .. common.title_prefix, "")
          ipc.class_of(name)
        end
      end,
    },
  },
})
