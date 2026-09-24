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
local home = require("hypr.scene.home")

local M = {}

-- A stray floats at the tiled box it happened to have, which on a wide monitor
-- is the whole screen and can sit partly off it. Float it at a sensible
-- fraction of its monitor instead, so it reads as a window rather than a
-- broken tile.
local WIDTH_FRACTION = 0.7
local HEIGHT_FRACTION = 0.8

-- A fraction alone does not survive an ultrawide. 0.7 of 5120 is 3584px of
-- window for a picker listing five projects, which is what it looked like:
-- a nearly empty pane most of a desk wide. A stray is a dialog -- a picker, a
-- confirmation, a one-off terminal -- and past roughly this size it stops
-- reading as one, so the fraction is a ceiling on small screens and these are
-- the ceiling on large ones. The laptop profile is untouched: 0.7 of 1920 is
-- already below the cap.
local MAX_WIDTH = 1280
local MAX_HEIGHT = 860

---The floating box a stray should take on `monitor`: a fraction of it, never
---larger than a dialog has any use for.
---@param monitor { width: integer, height: integer }
---@return integer width, integer height
function M.fit_size(monitor)
  local width = math.floor((monitor.width or 0) * WIDTH_FRACTION + 0.5)
  local height = math.floor((monitor.height or 0) * HEIGHT_FRACTION + 0.5)
  return math.min(width, MAX_WIDTH), math.min(height, MAX_HEIGHT)
end

---@class Scene.StrayDecision
---@field action "float"|"none"
---@field window HL.Window the window the triggering event fired for

---Whether `w` should be floated: its scene declares `strays = "float"`, its
---class matches no block (a member belongs to its block's own geometry, not
---the stray path) and is not `barred` (a scene-level class that legitimately
---opens unblocked, e.g. a launcher overlay — it stays exactly what it is),
---and it is not already floating (nothing to do, and re-dispatching a toggle
---on an already-floating window would tile it back), and no *other* active
---scene claims it: a class another active scene's block owns is not a real
---stray here, just a window that hasn't been re-homed yet
---(`hypr/scene/home.lua`) — floating it first would leave it floating once
---re-homing relocates it, since re-homing itself never fires (`action` stays
---`"none"`) for a window already standing on its own scene's workspace.
---@param spec Scene.Spec
---@param w HL.Window
---@param spec_by_scene table<string, Scene.Spec>? every scene, for the claim check above
---@param active table<string, true>? scene names active in the current mode
---@return Scene.StrayDecision
function M.decide(spec, w, spec_by_scene, active)
  if not w or not w.workspace or not layout.floats_strays(spec) then
    return { action = "none", window = w }
  end
  if spec_lib.block_for(spec, w.class, w.tags) then
    return { action = "none", window = w }
  end
  if spec_lib.class_matches(w.class, spec.barred) then
    return { action = "none", window = w }
  end
  if w.floating then
    return { action = "none", window = w }
  end
  if spec_by_scene and active and home.claim(spec_by_scene, active, w.class, w.tags) then
    return { action = "none", window = w }
  end
  return { action = "float", window = w }
end

return M
