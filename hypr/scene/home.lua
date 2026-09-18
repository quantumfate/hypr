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

---The name of the one active scene whose block claims `class`/`tags`, or nil.
---Only scenes active in the current mode are searched: a scene not admitted
---by the mode never claims a window away from wherever it stands
---(desktop-model.md "Mode-scoped"). Validation already refuses a mode where
---two active scenes claim the same class (`class_conflict`), so at most one
---match is ever possible here.
---@param spec_by_scene table<string, Scene.Spec>
---@param active table<string, true> scene names active in the current mode
---@param class string?
---@param tags string[]?
---@return string?
function M.claim(spec_by_scene, active, class, tags)
  for name in pairs(active) do
    local spec = spec_by_scene[name]
    if spec and spec_lib.block_for(spec, class, tags) then
      return name
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
  return { action = "move", window = w, workspace = home }
end

return M
