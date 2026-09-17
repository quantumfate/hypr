-- Session-only tile-order overrides for `mod+shift+h/l` tile swap.
--
-- Not persisted (never touches $QF_STORE): a swap is "how this desk looks
-- right now", not a scene edit. It lives only as long as this compositor
-- process; a restart or config reload reverts to the scene's declared order.
-- `hypr/scene/provider.lua` reads it every `recalculate`; `hypr/lib/nav.lua`
-- computes the swapped key order (pure), this module only stores it.
local M = {}

---@type table<string, string[]>
local overrides = {}

---@param scene_name string
---@return string[]? desired entry-key order, or nil for the declared order
function M.get(scene_name)
  return overrides[scene_name]
end

---@param scene_name string
---@param keys string[]
function M.set(scene_name, keys)
  overrides[scene_name] = keys
end

---For tests: drop every stored override.
function M.reset()
  overrides = {}
end

return M
