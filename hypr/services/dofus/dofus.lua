local dofus_launch = require("hypr.services.dofus.launch")
local common = require("hypr.services.dofus.common")
local team = require("hypr.services.dofus.team")
local swap = require("hypr.services.dofus.swap")
local ipc = require("hypr.services.dofus.ipc")
local qs = require("hypr.lib.qs")
local submap = require("hypr.lib.submap")
local drawer = require("hypr.lib.drawer")

local DOFUS_CLASS = "Dofus.x64"
local OVERLAY_CLASS = "Ankama Launcher"
local OVERLAY_TITLE = "overlay"

---Active window is a Dofus client?
---@return boolean
local function on_dofus()
  local active = hl.get_active_window()
  return active ~= nil and active.class == DOFUS_CLASS
end

---Active window is a launcher overlay?
---@return boolean
local function on_dofus_overlay()
  local active = hl.get_active_window()
  return active ~= nil and active.class == OVERLAY_CLASS and active.title == OVERLAY_TITLE
end

---@class DofusBindOpts
---@field desc string
---@field send_key? string key name to replay on passthrough (default: `key`)
---@field send_mods? string mods to replay on passthrough (default: "")
---@field mouse? boolean
---@field repeating? boolean
---@field release? boolean
---@field transparent? boolean
---@field non_consuming? boolean repeated keypresses, not a keypress-and-release pair

---Register a base-layer Dofus bind. On a Dofus window it runs `action`; off it,
---the key is forwarded to the focused window so nothing else notices the bind.
---@param key string full bind string (e.g. "F1", "SUPER + F10", "mouse:274")
---@param action function
---@param send_shortcut boolean sends a shortcut specified by `opts.send_mods` and
---`opts.send_key` to the active window instead of passing the buttons
---@param opts DofusBindOpts
---@param cond function
local function dofus_bind(key, action, send_shortcut, opts, cond)
  hl.bind(key, function()
    if cond() then
      action()
    elseif send_shortcut then
      hl.dispatch(hl.dsp.send_shortcut({
        mods = opts.send_mods or "",
        key = opts.send_key or key,
        window = "activewindow",
      }))
    else
      hl.dsp.pass({ window = "activewindow" })
    end
  end, {
    description = opts.desc,
    mouse = opts.mouse,
    repeating = opts.repeating,
    release = opts.release,
    transparent = opts.transparent,
    non_consuming = opts.non_consuming,
  })
end

-- F1..F8 → focus team member N (turn order = team.json order).
for i = 1, 8 do
  dofus_bind("F" .. i, function()
    team.activate(common.team(), i)
  end, true, { desc = "Dofus: activate team member " .. i }, on_dofus)
end

-- Turn-order cycling: arrows + spare F23 (a mouse-side button on some setups).
-- `right`/`F23` = next, `left`/SUPER+F23 = previous. Middle mouse is separate
-- below (press-all, not cycle).
dofus_bind(
  "SHIFT + right",
  function()
    team.iterate(common.team(), false)
  end,
  false,
  { desc = "Dofus: next team member", send_mods = "SHIFT", send_key = "right", non_consuming = true },
  on_dofus
)
dofus_bind(
  "SHIFT + left",
  function()
    team.iterate(common.team(), true)
  end,
  false,
  { desc = "Dofus: next team member", send_mods = "SHIFT", send_key = "left", non_consuming = true },
  on_dofus
)
dofus_bind("F23", function()
  team.iterate(common.team(), false)
end, true, { desc = "Dofus: next team member" }, on_dofus)
dofus_bind(config.main_mod .. " + F23", function()
  team.iterate(common.team(), true)
end, true, { desc = "Dofus: previous team member", send_key = "F23", send_mods = config.main_mod }, on_dofus)

hl.bind("mouse:274", function()
  if on_dofus() then
    team.press(common.team())
  elseif on_dofus_overlay() then
    hl.dispatch(hl.dsp.send_shortcut({
      mods = "CTRL",
      key = "v",
      window = "activewindow",
    }))
  end
end, { description = "Dofus: press current member (middle click)", non_consuming = true })

hl.bind("mouse:274", function()
  if on_dofus() then
    team.press(common.team())
  end
end, { description = "Dofus: press current member (middle click)", non_consuming = true })

-- Press the current member (single click at the cursor across the team).
dofus_bind("up", function()
  team.press(common.team())
end, true, { desc = "Dofus: press current member" }, on_dofus)

-- Detached double-click auto-clicker (already modified, so unambiguous).
dofus_bind(config.main_mod .. " + F10", function()
  team.double_click_start()
end, true, { desc = "Dofus: start double-click", send_key = "F10", send_mods = config.main_mod }, on_dofus)

dofus_bind(
  config.main_mod .. " + F11",
  function()
    team.double_click_stop()
  end,
  true,
  {
    desc = "Dofus: stop double-click",
    send_key = "F11",
    send_mods = config.main_mod,
    release = true,
    transparent = true,
  },
  on_dofus
)

-- The Dofus submap hosts management actions (launching, renaming, settings
-- copy, swap toggle, opening the team UI) plus store and roster queries —
-- nothing you need mid-fight, so no more team submaps and no team selection
-- here (the UI owns that).
submap.tree({
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
    {
      key = "a",
      desc = "Ankama launcher",
      -- The same press the shelf tree's own `a` performs, not a second
      -- behaviour: launch it when it is not running, slide its drawer in or
      -- out when it is. This key used to be a bare `exec_cmd`, so pressing it
      -- again with the launcher already parked on its shelf re-ran the launch
      -- and nothing moved — the launcher stayed exactly where it was, out of
      -- sight, with no way back to it from this tree.
      --
      -- The focus guard is not lost with the exec: it lives inside
      -- `,ankama-launcher.sh` (the drawer's declared `launch`), which refuses
      -- to start a session the active mode blocks and is only reached at all
      -- when no launcher window exists.
      action = function()
        drawer.press(drawer.by_id("ankama"))
      end,
    },
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
    {
      key = "p",
      desc = "Copy settings to all accounts",
      -- A held floating terminal, not a silent exec: the per-account copy log is
      -- the point, and `,copy-settings.sh` toasts the outcome once when it's
      -- done. BETA + EXPERIMENTAL by default; run the engine by hand for other
      -- channel flags.
      action = hl.dsp.exec_cmd(
        ("uwsm app -- %s --title 'Dofus settings copy' --hold -e ,copy-settings.sh"):format(
          config.apps.terminal_float.cmd
        )
      ),
    },
    {
      key = "r",
      desc = "Reload team store",
      action = function()
        ipc.reload()
      end,
    },
    {
      key = "o",
      desc = "Show roster",
      action = function()
        qs.notify("Dofus roster", "dofus", "team")
      end,
    },
    {
      key = "s",
      mods = { "SHIFT" },
      desc = "Selected team",
      action = function()
        qs.notify("Dofus team", "dofus", "selected")
      end,
    },
  },
})

-- MOD+H/L used to move window focus generically here, cycling the Dofus
-- group instead on a Dofus window (`dofus_team.nav`) — registered before
-- `hypr/binds.lua`'s scene-aware tile navigation (`hypr.services` loads
-- ahead of `hypr.binds` in `hypr/init.lua`), so it silently shadowed that
-- bind for every chord it claimed (Hyprland keeps the first registration;
-- AGENTS.md "Hyprland primitives"). LEO-380 folds the Dofus case into the
-- one pure decision instead: a Dofus group is one tile for `mod+h/l`, and
-- `mod+j/k` cycles it via the Dofus group adapter
-- (`hypr/scene/group_adapters.lua`), so this separate bind is retired
-- rather than fixed in place.
