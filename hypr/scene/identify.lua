-- Launch-time identity stamping for same-class windows (LEO-364).
--
-- Apps set their own class; the compositor cannot rewrite it, so two windows
-- of one class (dofus and media both launch the shared `zen-twilight-media`
-- profile) are otherwise indistinguishable to a scene's block match. A block
-- that declares `slot` (hypr/scene/spec.lua) only claims a window already
-- carrying the Hyprland tag `slot:<slot>`; this module is what stamps that
-- tag, once, on whichever live window is still missing one.
--
-- Verified live (LEO-364, same finding as LEO-369's compile-time case): a
-- tag added to an already-mapped window does not retroactively fire a
-- Hyprland rule matched on that tag — a rule only ever sees the tags a
-- window already carried when it opened. That is not a problem here because
-- nothing chains a *compile-time* rule off a slot tag: scene claims read
-- `w.tags` straight from the live window, in this same Lua event pass, the
-- same way grouping.lua and strays.lua already decide at runtime instead of
-- through a static rule (AGENTS.md "Hyprland primitives").
--
-- Pure: this module returns a tag to stamp, never calls `hl`. The executor
-- (hypr/events/scene.lua) dispatches and logs it.
local spec_lib = require("hypr.scene.spec")

local M = {}

---@param tags string[]?
---@param tag string
---@return boolean
local function has_tag(tags, tag)
  for _, t in ipairs(tags or {}) do
    if t == tag then
      return true
    end
  end
  return false
end

---Every slot tag `hl.dsp.window.tag` has already put on some window on
---`workspace_name` in `live` (`w` excluded, since `w` is what wants a slot,
---not what has one) — derived fresh from live windows on every call, the
---same "no remembered set" rule grouping.lua's join-target search follows.
---@param workspace_name string
---@param w_address string
---@param live HL.Window[]
---@return table<string, boolean>
local function taken_slots(workspace_name, w_address, live)
  local taken = {}
  for _, other in ipairs(live) do
    if other.address ~= w_address and other.workspace and other.workspace.name == workspace_name then
      for _, tag in ipairs(other.tags or {}) do
        taken[tag] = true
      end
    end
  end
  return taken
end

---The `slot:<slot>` tag `w` should be stamped with, or nil if `w`'s class
---names no slot block, `w` already carries one of its slots, or every slot
---for this class is already held by a live sibling (the class is
---over-subscribed; the extra window is left for `strays` to place, same as
---any other unclaimed window). Slot ownership is scoped to `workspace_name`,
---not necessarily the workspace `w` stands on: a launch-claimed window can
---map elsewhere first (LEO-412, the shared profile's pin), and the slots it
---is competing for are its scene's, not its current workspace's.
---@param spec Scene.Spec
---@param w HL.Window
---@param live HL.Window[] `hl.get_windows()`, or a stub's stand-in
---@param workspace_name string the workspace whose taken slots are consulted
---@return string? tag
function M.assign_for(spec, w, live, workspace_name)
  if not spec or not w or not w.workspace or not w.address or not workspace_name then
    return nil
  end
  local slots = spec_lib.slot_candidates(spec, w.class)
  if #slots == 0 then
    return nil
  end
  for _, block in ipairs(slots) do
    if has_tag(w.tags, "slot:" .. block.slot) then
      return nil -- already stamped
    end
  end
  local taken = taken_slots(workspace_name, w.address, live)
  for _, block in ipairs(slots) do
    local tag = "slot:" .. block.slot
    if not taken[tag] then
      return tag
    end
  end
  return nil -- every slot for this class is already held
end

---The `slot:<slot>` tag `w` should be stamped with for the scene its own
---workspace picks (the arrival-order path: pokemon's chat/stream windows open
---directly on the pokemon workspace and are told apart by identify alone).
---@param spec Scene.Spec
---@param w HL.Window
---@param live HL.Window[] `hl.get_windows()`, or a stub's stand-in
---@return string? tag
function M.assign(spec, w, live)
  return M.assign_for(spec, w, live, w and w.workspace and w.workspace.name)
end

return M
