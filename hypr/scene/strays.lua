-- Open-time stray-float decisions (LEO-367).
--
-- `strays = "float"` used to be a layout fiction: `hypr/scene/layout.lua`
-- pulled a stray out of the split and gave it a centered *tiled* box instead
-- of truly floating it, because a layout provider has no non-dispatch
-- primitive to toggle `floating` (docs/scenes.md "Strays"). A tile is still a
-- tile even when it is alone in a box, so it could be drawn behind the
-- scene's real tiles.
--
-- Same fix as grouping (hypr/scene/grouping.lua): decide at runtime, once per
-- `window.open`/`window.move_to_workspace`, against the live window. A
-- compile-time rule chained off `match.workspace` cannot do this (AGENTS.md
-- "Hyprland primitives", LEO-369) — `workspace` in `match` is not true yet
-- when the window opens, so a static `float = true` rule fed by it never
-- fires.
--
-- Pure: this module returns a decision, never calls `hl`. The executor
-- (hypr/events/scene.lua) dispatches and logs it.
local spec_lib = require("hypr.scene.spec")
local layout = require("hypr.scene.layout")

local M = {}

---@class Scene.StrayDecision
---@field action "float"|"none"
---@field window HL.Window the window the triggering event fired for

---Whether `w` should be floated: its scene declares `strays = "float"`, its
---class matches no block (a member belongs to its block's own geometry, not
---the stray path) and is not `barred` (a scene-level class that legitimately
---opens unblocked, e.g. a launcher overlay — it stays exactly what it is),
---and it is not already floating (nothing to do, and re-dispatching a toggle
---on an already-floating window would tile it back).
---@param spec Scene.Spec
---@param w HL.Window
---@return Scene.StrayDecision
function M.decide(spec, w)
  if not w or not w.workspace or not layout.floats_strays(spec) then
    return { action = "none", window = w }
  end
  if spec_lib.block_for(spec, w.class) then
    return { action = "none", window = w }
  end
  if spec_lib.class_matches(w.class, spec.barred) then
    return { action = "none", window = w }
  end
  if w.floating then
    return { action = "none", window = w }
  end
  return { action = "float", window = w }
end

return M
