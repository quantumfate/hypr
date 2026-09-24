-- Persisted per-column deck state (docs/deck.md "Flipping (scrolling)").
--
-- The window ORDER a column's strip walks and the visible index into it.
-- Window addresses survive a compositor reload or a scene-redraw, so the
-- strip is rebuilt the way the user built it rather than in whatever order
-- the compositor re-enumerates windows afterwards; the scroll index survives
-- so a reload does not yank a column off a position chosen by hand. Unlike
-- the session-only `hypr/scene/order.lua` tile-swap override, this state is
-- deliberate: it IS the user's arrangement of the column.
--
-- $QF_STORE/deck-order.json, shape:
--   { [scene] = { [column_order] = { order = string[], scroll = number } } }
-- `order` is the column's whole window-address list, newest arrival last —
-- exactly `deck.stacks`'s output for that column with the recorded order fed
-- in, `map`-style replacements included. `scroll` is the 1-based visible
-- index into the thing list (single window or whole collapsed group);
-- `hypr/scene/deck.lua`'s `clamp_scroll` re-derives a valid index wherever
-- it is read, so a closed window can never strand the stored position.
--
-- This module is the store's read/write seam only: re-ordering is
-- `deck.stacks`'s, deciding what is new is `deck_provider`'s, and navigation
-- arithmetic is nav's. Every write is dirty-guarded — a column record that
-- equals what is already stored is not written, because a write bumps the
-- file's mtime and that is what the desk reacts to; a no-op must not look
-- like change.
local Store = require("hypr.lib.store")
local HANDLE = Store.define("deck-order")

local M = {}

---Whether two address lists hold the same addresses in the same order.
---@param a string[]
---@param b string[]
---@return boolean
local function same_order(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

---Read-modify-write one column's record, persisted only when it changed.
---The record defaults to `{ order = {}, scroll = nil }` when nothing was
---stored yet, so a caller can grow it without asking first. The lived-on
---record is a COPY of whatever the store cached: a caller reordering it can
---never corrupt the cache through the shared array, and the dirty compare
---below is against the cache's own values.
---@param scene_name string
---@param column_order integer
---@param fn fun(record: { order: string[], scroll: number? }): nil
---@return { order: string[], scroll: number? } the record as persisted
local function update(scene_name, column_order, fn)
  local doc = HANDLE:get() or {}
  local scene = {}
  for k, v in pairs(doc[scene_name] or {}) do
    scene[k] = v
  end
  local old = scene[column_order]
  local record = { order = {}, scroll = old and old.scroll }
  for _, address in ipairs((old and old.order) or {}) do
    record.order[#record.order + 1] = address
  end
  fn(record)
  if old == nil or old.scroll ~= record.scroll or not same_order(old.order or {}, record.order) then
    scene[column_order] = record
    local next_doc = {}
    for k, v in pairs(doc) do
      next_doc[k] = v
    end
    next_doc[scene_name] = scene
    HANDLE:put(next_doc)
  end
  return record
end

---One column's record, or nil when nothing was ever recorded for it.
---@param scene_name string
---@param column_order integer
---@return { order: string[], scroll: number? }?
function M.get(scene_name, column_order)
  local scene = HANDLE:get(scene_name)
  return scene and scene[column_order] or nil
end

---Every recorded column for one scene, keyed by column order — the full
---pass `deck_provider` places all columns at once and `nav.deck_tile_order`
---walks with. Copies, so a caller re-ordering or mutating cannot leak into
---the store's cached decode.
---@param scene_name string
---@return table<integer, { order: string[], scroll: number? }>
function M.get_all(scene_name)
  local scene = HANDLE:get(scene_name)
  local out = {}
  for order, record in pairs(scene or {}) do
    local copy = { order = {}, scroll = record.scroll }
    for _, address in ipairs(record.order or {}) do
      copy.order[#copy.order + 1] = address
    end
    out[order] = copy
  end
  return out
end

---Replace one column's record: the whole address order and the visible
---index. Dirty-guarded by value, so a converged-pass write that would store
---exactly what is already there is a no-op, per the module comment.
---@param scene_name string
---@param column_order integer
---@param order string[] the column's window-address list, newest arrival last
---@param scroll number? the 1-based visible index, clamped by readers
---@return { order: string[], scroll: number? }
function M.record(scene_name, column_order, order, scroll)
  return update(scene_name, column_order, function(record)
    record.order = order
    record.scroll = scroll
  end)
end

---Update only the visible index of one column, keeping its recorded order.
---`mod+ctrl+j/k`'s scroll bind calls this after computing the new position.
---@param scene_name string
---@param column_order integer
---@param index integer
---@return { order: string[], scroll: number? }
function M.set_scroll(scene_name, column_order, index)
  return update(scene_name, column_order, function(record)
    record.scroll = index
  end)
end

---Drop a closed window's address from every recorded column across every
---scene (docs/deck.md "Flipping (scrolling)", "Fall-through"): an address
---the compositor later hands to a different window would otherwise read as
---already-seen and its column would not scroll to it. Called from the
---`window.close` hook, the only event that can retire an address.
---@param address string?
function M.forget(address)
  if not address then
    return
  end
  local doc = HANDLE:get() or {}
  local next_doc = {}
  local changed = false
  for scene_name, scene in pairs(doc) do
    local next_scene = {}
    for order, record in pairs(scene) do
      local order_list = record.order or {}
      local kept = {}
      for _, addr in ipairs(order_list) do
        if addr ~= address then
          kept[#kept + 1] = addr
        end
      end
      if #kept ~= #order_list then
        changed = true
      end
      next_scene[order] = { order = kept, scroll = record.scroll }
    end
    next_doc[scene_name] = next_scene
  end
  if changed then
    HANDLE:put(next_doc)
  end
end

---For tests: drop every record.
function M.reset()
  HANDLE:put({})
end

return M
