-- Session-only scroll index per deck workspace/column (docs/deck.md
-- "Scrolling"). Mirrors hypr/scene/order.lua exactly: never touches
-- $QF_STORE, lives only as long as this compositor process, and is a plain
-- store the provider reads and the nav binds write — no arithmetic here,
-- that is hypr/scene/deck.lua's `clamp_scroll`.
local M = {}

---@type table<string, table<integer, integer>>
local scroll = {}

---@param scene_name string
---@param column_order integer
---@return integer? 1-based visible index, nil when nothing has scrolled yet
function M.get(scene_name, column_order)
  local columns = scroll[scene_name]
  return columns and columns[column_order]
end

---@param scene_name string
---@return table<integer, integer> column order -> index, for a full pass
---(`hypr/scene/deck.lua`'s `M.boxes` `opts.scroll`) rather than one column
---at a time.
function M.get_all(scene_name)
  return scroll[scene_name] or {}
end

---@param scene_name string
---@param column_order integer
---@param index integer
function M.set(scene_name, column_order, index)
  scroll[scene_name] = scroll[scene_name] or {}
  scroll[scene_name][column_order] = index
end

---For tests: drop every stored index.
function M.reset()
  scroll = {}
end

return M
