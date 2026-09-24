-- Publishing a scene's resolved docks (docs/scenes.md "Docks").
--
-- `hypr/lib/dock.lua` decides where an isle sits; this module is the seam
-- between that pure decision and the `geometry` store quickshell reads. It is
-- called from the tail of a layout pass, once the boxes are known, because a
-- docked region moves with the tile it hangs off.
--
-- Two rules keep the tail read-only, which is what stops a dock from feeding
-- back into the layout that produced it:
--
--   * nothing here places, dispatches or re-enters `recalculate`; and
--   * the store is written only when the resolved map actually differs from
--     what was published last, so a recalculate storm is one write, not one
--     per pass.
local dock = require("hypr.lib.dock")
local Store = require("hypr.lib.store")

local M = {}

local geometry_store = Store.define("geometry")

-- The last map published per monitor, so an unchanged pass writes nothing.
-- Purely a write-suppressor: losing it (a reload) costs one extra write, and
-- the published value is derived from live geometry either way.
local last = {}

---Two published maps, compared by value. Small tables (one entry per declared
---isle, five numbers each), so a plain walk is cheaper than encoding both.
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

---The targets a dock's `of` can name, built from what the layout just placed:
---`block:<order>`, `slot:<slot>` and `class:<class>`, each pointing at the box
---of the first tile that answers to it. A block with no live window names no
---target at all, which is exactly what makes its dock collapse.
---@param scene Scene.Spec
---@param tiles Scene.Tile[]
---@param boxes Scene.Box[]
---@param spec_lib table the scene spec module (passed in to avoid a cycle)
---@return table<string, Dock.Box>
function M.targets(scene, tiles, boxes, spec_lib)
  local by_address = {}
  for _, box in ipairs(boxes or {}) do
    by_address[box.address] = box
  end

  local targets = {}
  for _, tile in ipairs(tiles or {}) do
    local box = by_address[tile.address]
    if box then
      local key = "class:" .. (tile.class or "")
      targets[key] = targets[key] or box
      for _, tag in ipairs(tile.tags or {}) do
        local slot = tag:match("^slot:(.+)$")
        if slot then
          targets["slot:" .. slot] = targets["slot:" .. slot] or box
        end
      end
      local block = spec_lib.block_for(scene, tile.class, tile.tags)
      if block and block.order then
        local key_block = "block:" .. tostring(block.order)
        targets[key_block] = targets[key_block] or box
      end
    end
  end
  return targets
end

---Overlay each placed box with the rect its window actually occupies.
---
---A layout `place()` is a REQUEST. What the compositor finally gives the
---window is that box adjusted by its own inner gap and border, and the two
---differ by tens of pixels — on this desk a deck column's box was 21px wider
---per side than the window standing in it. An isle docked to the box was
---therefore docked to an edge nothing was drawn at, on every axis at once.
---The window's own rect is the only geometry that answers "where is the edge
---I am lining up with", so it wins wherever it is known; a window the
---compositor has not reported yet keeps its placed box.
---@param boxes Scene.Box[] the boxes this pass placed
---@param rects table<string, Dock.Box>? address -> the window's live rect
---@return Scene.Box[]
function M.settled(boxes, rects)
  if not rects then
    return boxes or {}
  end
  local out = {}
  for _, box in ipairs(boxes or {}) do
    local live = box.address and rects[box.address]
    if live then
      out[#out + 1] = { address = box.address, x = live.x, y = live.y, w = live.w, h = live.h }
    else
      out[#out + 1] = box
    end
  end
  return out
end

---Resolve and publish one scene's docks for one monitor.
---
---Coordinates are monitor-local, because a layer surface is positioned within
---its own output and knows nothing of the desk's global origin.
---@param opts {
---  scene: Scene.Spec,
---  monitor: { name: string, x: number, y: number, width: number, height: number },
---  tiles: Scene.Tile[],
---  boxes: Scene.Box[],
---  gaps_in: number,
---  gaps_out: table<string, number>,
---  spec_lib: table,
--- }
function M.publish(opts)
  local scene, monitor = opts.scene, opts.monitor
  if not (scene and monitor and monitor.name) then
    return
  end

  local origin_x, origin_y = monitor.x or 0, monitor.y or 0
  local function local_box(box)
    return { x = box.x - origin_x, y = box.y - origin_y, w = box.w, h = box.h }
  end

  local targets = {}
  for key, box in pairs(M.targets(scene, opts.tiles, opts.boxes, opts.spec_lib)) do
    targets[key] = local_box(box)
  end

  local boxes = {}
  for _, box in ipairs(opts.boxes or {}) do
    boxes[#boxes + 1] = local_box(box)
  end

  local resolved = dock.resolve(scene.docks, {
    monitor = { x = 0, y = 0, w = monitor.width or 0, h = monitor.height or 0 },
    targets = targets,
    boxes = boxes,
    gaps_out = opts.gaps_out or {},
    gaps_in = opts.gaps_in or 0,
  })

  if same(last[monitor.name], resolved) then
    return
  end
  last[monitor.name] = resolved

  -- `set` shallow-merges the top-level key. `put` would REPLACE the whole
  -- document, taking `monitors`, `roles` and `workspaces` with it.
  local published = geometry_store:get("docks") or {}
  published[monitor.name] = resolved
  geometry_store:set({ docks = published })
end

---Drop the published docks of every monitor not named in `keep`.
---
---A dock map is written from the tail of a layout pass, so a monitor whose
---workspace stops declaring docks -- or stops having tiles at all -- never
---writes again and its last map stands forever. That stale map is not merely
---old: it is another scene's boxes under this monitor's name, so the isles it
---describes sit wherever that other monitor's windows were. Sweeping on a
---workspace switch is what retires it.
---@param keep table<string, boolean> monitor names whose docks still stand
function M.sweep(keep)
  local published = geometry_store:get("docks")
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
    geometry_store:set({ docks = published })
  end
end

---Forget what was published, so the next pass writes again. The scene
---declaration changing under a running desk is the case: the resolved map may
---be identical by value while the declaration that produced it is not.
function M.invalidate()
  last = {}
end

return M
