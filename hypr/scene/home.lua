-- Re-homing a claimed window to its scene's workspace (LEO-353).
--
-- `collect` used to be declaration metadata nothing executed (docs/scenes.md
-- "Collect"). The product decision replacing it: a window claimed by a
-- scene's block is re-homed to that scene's workspace unconditionally,
-- whenever it opens and whenever a mode applies — not gated on a per-block
-- flag. `collect` is retired; see hypr/scene/spec.lua's header for where the
-- field used to live.
--
-- Pure: this module returns a decision, never calls `hl`. The executor
-- (hypr/events/scene.lua for the open case, hypr/hyprfocus/init.lua for the
-- mode-apply case) dispatches and logs it.
local spec_lib = require("hypr.scene.spec")

local M = {}

---@class Scene.HomeDecision
---@field action "move"|"none"
---@field window HL.Window the window the decision is about
---@field workspace string? move: the scene workspace it belongs on
---@field settle boolean? move: also clear a float the window is carrying

---The one `slot:<slot>` the tags carry, or nil when tagless or when two slots
---sit on one window (a double stamp is corrupt state; fall back to the
---class-wide search and let the declaration's own `ambiguous_classes` story
---decide).
---@param tags string[]?
---@return string?
local function carried_slot(tags)
  local slot
  for _, tag in ipairs(tags or {}) do
    local s = tag:match("^slot:(.+)$")
    if s then
      if slot then
        return nil
      end
      slot = s
    end
  end
  return slot
end

---The first block declaring exactly `slot` for `class`, in declaration order.
---@param spec Scene.Spec
---@param class string?
---@param slot string
---@return Scene.Block?
local function block_declaring(spec, class, slot)
  for _, block in ipairs(spec.blocks) do
    if block.slot == slot and spec_lib.class_matches(class, block.classes) then
      return block
    end
  end
  return nil
end

---The name of the one active scene whose block claims `class`/`tags`, or nil.
---Only scenes active in the current mode are searched: a scene not admitted
---by the mode never claims a window away from wherever it stands
---(desktop-model.md "Mode-scoped"). Validation already refuses a mode where
---two active scenes claim the same class (`class_conflict`), so at most one
---match is ever possible here.
---
---A window carrying a `slot:<slot>` tag is claimed by the scene that declared
---that slot, never by another active scene's bare same-class block (LEO-412,
---the shared profile's desk: dofus and media name the profile class, and
---media's bare block must not swallow a window claimed for dofus). The
---resolver keys a slot block as `class:slot`
---(hypr/hyprfocus/resolve.lua); this is the runtime half of the same claim
---discipline.
---@param spec_by_scene table<string, Scene.Spec>
---@param active table<string, true> scene names active in the current mode
---@param class string?
---@param tags string[]?
---@return string?
function M.claim(spec_by_scene, active, class, tags)
  local slot = carried_slot(tags)
  for name in pairs(active) do
    local spec = spec_by_scene[name]
    if spec then
      if slot and block_declaring(spec, class, slot) or not slot and spec_lib.block_for(spec, class, tags) then
        return name
      end
    end
  end
  return nil
end

---Whether `w` stands on a special workspace: a shelf drawer, the engine's own
---hold area, or any other special. None of those are a scene's territory and
---none may be moved out from under the engine that owns them.
---@param w HL.Window?
---@return boolean
local function on_special(w)
  local name = w and w.workspace and w.workspace.name
  return type(name) == "string" and name:match("^special:") ~= nil
end

---The one decision `w` needs: move it home, or leave it exactly where it is.
---@param spec_by_scene table<string, Scene.Spec>
---@param active table<string, true> scene names active in the current mode
---@param w HL.Window
---@return Scene.HomeDecision
function M.decide(spec_by_scene, active, w)
  if not w or not w.workspace or on_special(w) then
    return { action = "none", window = w }
  end
  local home = M.claim(spec_by_scene, active, w.class, w.tags)
  if not home or w.workspace.name == home then
    return { action = "none", window = w }
  end
  -- A claimed window can arrive floating: it opened before this
  -- decision claimed it, so the open-time stray-float path on its wrong
  -- workspace floated it for real. Re-homing must not just relocate a float
  -- to the right desk — the scene it belongs to never declared it floating,
  -- so it must land tiled. `w.floating` is only ever true here for a window
  -- this decision itself is about to move: a window already on its scene's
  -- workspace never reaches this branch, so a deliberate user float there is
  -- never touched.
  return { action = "move", window = w, workspace = home, settle = w.floating or nil }
end

return M
