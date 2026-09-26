-- Publishing a scene's placed areas (docs/scenes.md "Areas").
--
-- Same seam as `hypr/scene/dock_publish.lua`, for the same reason: a
-- read-only tail of the layout pass, called once boxes are known, because
-- `work`/`columns` are measured off geometry the pass just placed. Nothing
-- here places, dispatches, or re-enters `recalculate`, and a write happens
-- only when the resolved map actually differs from what was published last.
local area = require("hypr.lib.area")
local Store = require("hypr.lib.store")

local M = {}

local geometry_store = Store.define("geometry")

-- The last map published per monitor, so an unchanged pass writes nothing.
local last = {}

---Two published maps, compared by value.
---@param a table?
---@param b table?
---@return boolean
local function same(a, b)
  if a == nil or b == nil then
    return a == b
  end
  for key, left in pairs(a) do
    local right = b[key]
    if type(left) == "table" then
      if type(right) ~= "table" or not same(left, right) then
        return false
      end
    elseif left ~= right then
      return false
    end
  end
  for key in pairs(b) do
    if a[key] == nil then
      return false
    end
  end
  return true
end

---Resolve and publish one scene's areas for one monitor.
---@param opts {
---  scene_name: string,
---  monitor_name: string,
---  work: { x: number, y: number, w: number, h: number },
---  columns_by_order: table<integer, { x: number, y: number, w: number, h: number }>?,
--- }
function M.publish(opts)
  if not (opts and opts.scene_name and opts.monitor_name and opts.work) then
    return
  end
  local resolved = area.build(opts.scene_name, opts.work, opts.columns_by_order)
  if same(last[opts.monitor_name], resolved) then
    return
  end
  last[opts.monitor_name] = resolved

  -- `set` shallow-merges the top-level key, like `dock_publish`'s `write`;
  -- `put` would replace the whole document.
  local published = geometry_store:get("areas") or {}
  published[opts.monitor_name] = resolved
  geometry_store:set({ areas = published })
end

---Drop the published areas of every monitor not named in `keep`, mirroring
---`dock_publish.M.sweep`: a monitor whose workspace stops showing a scene
---never writes again, so its last map otherwise stands forever.
---@param keep table<string, boolean>
function M.sweep(keep)
  local published = geometry_store:get("areas")
  if type(published) ~= "table" then
    return
  end
  local dropped = false
  for name in pairs(published) do
    if not keep[name] then
      published[name] = nil
      last[name] = nil
      dropped = true
    end
  end
  if dropped then
    geometry_store:set({ areas = published })
  end
end

---Forget what was published, so the next pass writes again — a declaration
---re-read (LEO-397) may resolve a different area from the same-valued boxes.
function M.invalidate()
  last = {}
end

return M
