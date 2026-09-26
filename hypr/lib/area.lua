-- Area arithmetic: a scene's `work` box and its column boxes, as four
-- corners each (docs/scenes.md "Areas"). Pure, same discipline as
-- `hypr/lib/dock.lua`: boxes go in, corners come out. No `hl`, no store.
local M = {}

---@class Area.Point
---@field x number
---@field y number

---@class Area.Corners
---@field top_left Area.Point
---@field top_right Area.Point
---@field bottom_left Area.Point
---@field bottom_right Area.Point

---A box's four corners, monitor-local.
---@param box { x: number, y: number, w: number, h: number }
---@return Area.Corners
function M.corners(box)
  return {
    top_left = { x = box.x, y = box.y },
    top_right = { x = box.x + box.w, y = box.y },
    bottom_left = { x = box.x, y = box.y + box.h },
    bottom_right = { x = box.x + box.w, y = box.y + box.h },
  }
end

---The published shape for one monitor+scene: `work`'s corners plus every
---column's, keyed by its declared `order` as a string (JSON has no integer
---keys). A scene with no column concept is keyed by block order instead —
---the caller decides which map it hands in as `columns_by_order`.
---@param scene_name string
---@param work { x: number, y: number, w: number, h: number }
---@param columns_by_order table<integer, { x: number, y: number, w: number, h: number }>?
---@return table
function M.build(scene_name, work, columns_by_order)
  local columns = {}
  for order, box in pairs(columns_by_order or {}) do
    columns[tostring(order)] = M.corners(box)
  end
  return { scene = scene_name, work = M.corners(work), columns = columns }
end

return M
