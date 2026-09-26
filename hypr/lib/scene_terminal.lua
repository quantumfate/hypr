-- The ad-hoc terminal class a scene admits.
--
-- `mod+return` opens "a terminal here", and "here" is a scene: `code`'s
-- terminals are `Kitty-code`, `knowledge`'s are `Kitty-knowledge`. One class
-- per scene, because a mode admits a class exactly once -- two scenes both
-- claiming `Kitty-Main` is a refused mode, not a shared terminal -- and
-- because a scene can then give its own terminals a column
-- (docs/declared-groups.md).
--
-- A scene opts in by declaring the class in one of its blocks. A scene that
-- declares none, and every workspace with no scene at all, keeps the plain
-- `Kitty-Main`: nothing about the generic terminal changes off a scene that
-- asked for its own.
local spec_lib = require("hypr.scene.spec")

local M = {}

M.PREFIX = "Kitty-"

---The class name a scene's own terminals carry.
---@param scene_name string
---@return string
function M.class_for(scene_name)
  return M.PREFIX .. scene_name
end

---Whether `scene` declares a block admitting its own terminal class.
---@param scene Scene.Spec?
---@param scene_name string
---@return boolean
function M.declares(scene, scene_name)
  local wanted = M.class_for(scene_name)
  for _, block in ipairs((scene and scene.blocks) or {}) do
    for _, class in ipairs(block.classes or {}) do
      if class == wanted then
        return true
      end
    end
  end
  return false
end

---The terminal class for the workspace the keyboard is on: the scene's own
---when it declares one, the plain terminal otherwise.
---@return string
function M.class_for_focused()
  local fallback = (rawget(_G, "config") or {}).apps and config.apps.terminal.class or "Kitty-Main"
  local name = require("hypr.events.seat").workspace()
  if not name then
    return fallback
  end
  local scene = (spec_lib.load() or {})[name]
  if scene and M.declares(scene, name) then
    return M.class_for(name)
  end
  return fallback
end

return M
