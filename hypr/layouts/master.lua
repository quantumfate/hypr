hl.config({
  master = {
    new_status = "inherit",
    orientation = "left",
    new_on_active = "after",
    mfact = 0.70,
    center_master_fallback = "right",
    always_keep_position = false,
    slave_count_for_center_master = 2,
  },
})

local layout = require("hypr.lib.layout")

-- Hyprland's master algorithm (which monocle also runs on) walks a ring of
-- tiled targets; a layoutmsg that reaches getNextTarget() with an empty or
-- single-entry ring has segfaulted the compositor before (v0.55.4, SIGSEGV in
-- CMasterAlgorithm::getNextTarget). Every master layoutmsg goes through this
-- guard so a stray keypress on an empty or one-window workspace is a no-op
-- instead of taking the session down.
---@return integer count of tiled, mapped windows on the active workspace
local function tiled_count()
  local ws = hl.get_active_special_workspace() or hl.get_active_workspace()
  if not ws then
    return 0
  end
  local n = 0
  for _, w in ipairs(hl.get_windows()) do
    if w.workspace and w.workspace.id == ws.id and w.mapped and not w.floating then
      n = n + 1
    end
  end
  return n
end

---Wrap a layoutmsg so it only fires with enough tiled windows to be meaningful.
---@param msg string layoutmsg argument, e.g. "cyclenext"
---@param min integer? minimum tiled windows required (default 2)
---@return fun()
local function guarded(msg, min)
  return function()
    if tiled_count() < (min or 2) then
      return
    end
    hl.dispatch(hl.dsp.layout(msg))
  end
end

-- master + monocle are a linear stack: left/down walk the ring one way,
-- right/up the other. swap_* falls back to directional window.swap.
local cycle = {
  focus_left = guarded("cycleprev"),
  focus_down = guarded("cycleprev"),
  focus_right = guarded("cyclenext"),
  focus_up = guarded("cyclenext"),
}
layout.register("master", cycle)
layout.register("monocle", cycle)

-- Master-specific ops: SUPER+x -> m -> key.
layout.register_submap({
  layout = "master",
  key = "m",
  entries = {
    { key = "m", desc = "Master: swap active with the master window", action = guarded("swapwithmaster auto") },
    { key = "f", desc = "Master: focus the master window", action = guarded("focusmaster auto") },
    { key = "a", desc = "Master: add a master slot", action = guarded("addmaster") },
    { key = "d", desc = "Master: remove a master slot", action = guarded("removemaster") },
    { key = "o", desc = "Master: cycle orientation", action = guarded("orientationnext", 1) },
  },
})
