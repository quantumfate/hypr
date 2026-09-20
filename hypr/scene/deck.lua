-- Where a deck-layout scene's windows go, as arithmetic.
--
-- Pure, mirroring hypr/scene/layout.lua: a scene, the tiles present, the
-- scroll position per column, and the work area go in; a box per member
-- comes out — the visible one at its column's ordinary geometry, every
-- other member of the same column moved off-screen along the vertical axis.
-- No `hl`, no dispatch, no timers. See docs/deck.md for the contract this
-- implements.
--
-- LEO-402: parking a hidden member on another workspace (the prior "hold"
-- design, superseded — see git history and docs/deck.md's "Why hidden
-- members are placed off-screen") cannot be animated, because moving a
-- window to a different workspace fires none of this build's animation
-- leaves (not a map/unmap, not a same-workspace reposition, and the special
-- workspace is never shown) — scrolling read as a cut, once, then never
-- animated again. Keeping every member tiled on the SAME workspace and
-- moving the hidden ones vertically off-screen instead is an ordinary
-- `windowsMove`-animated reposition, which is what makes the strip read as
-- scrolling. LEO-349's live spike (kept here as history) found a naive
-- off-screen `target:place` got silently restacked back into view inside a
-- custom-registered layout; this module now does it again against the
-- `scene` layout's own `recalculate`, per LEO-402's sketch. Unverified live
-- in this environment (no nested Wayland session available to boot
-- `just e2e-up` here) — see docs/deck.md's live-verification note.

local layout = require("hypr.scene.layout")

local M = {}

local MIN_COLUMNS = 1
local MAX_COLUMNS = 3

---@class Deck.Column
---@field order integer left-to-right position, 1..3
---@field share number? fraction of the row this column holds
---@field classes string[]? literal class or Lua pattern subscribing a window
---@field deck string? subscription name: a window carrying the Hyprland tag
---`deck:<name>` joins this column regardless of class (a window "declaring
---itself in"), the same identity-tag pattern as a scene block's `slot`

---@class Deck.Spec
---@field name string workspace default_name
---@field columns Deck.Column[] 1..3 entries, sorted by `order`

---Whether a scene's declaration opts into the deck layout. Every scene
---defaults to `scene` (fixed blocks); `layout = "deck"` is the one opt-in.
---A scene that never sets it — Dofus included — keeps `scene` and must
---never see scroll/flip behaviour.
---@param scene { layout: string? }
---@return boolean
function M.applies(scene)
  return scene ~= nil and scene.layout == "deck"
end

---Whether `tags` carries the deck self-declaration `deck:<name>`.
---@param tags string[]?
---@param name string
---@return boolean
local function has_deck_tag(tags, name)
  for _, t in ipairs(tags or {}) do
    if t == "deck:" .. name then
      return true
    end
  end
  return false
end

---The column a tile subscribes to: by `classes` pattern match (the same
---grammar `hypr/scene/spec.lua`'s `class_matches` uses), or by carrying the
---column's own `deck:<name>` tag — a window declaring itself in without its
---class being listed at all. First match by column `order`, deterministic
---like `spec.block_for`.
---@param spec Deck.Spec
---@param tile Scene.Tile
---@return Deck.Column?
function M.column_for(spec, tile)
  for _, column in ipairs(spec.columns) do
    if column.deck and has_deck_tag(tile.tags, column.deck) then
      return column
    end
  end
  for _, column in ipairs(spec.columns) do
    if column.classes then
      for _, entry in ipairs(column.classes) do
        if tile.class == entry or (tile.class and tile.class:match("^(" .. entry .. ")$")) then
          return column
        end
      end
    end
  end
  return nil
end

---Every tile grouped by the column it subscribes to, in arrival order
---within each column — the column's "deck" of windows, unclaimed tiles
---dropped (a deck scene has no stray catch-all; every column names its own
---membership explicitly, unlike a `scene` block's fallback strays).
---@param spec Deck.Spec
---@param tiles Scene.Tile[]
---@return table<integer, Scene.Tile[]> stacks keyed by column order
function M.stacks(spec, tiles)
  local out = {}
  for _, tile in ipairs(tiles) do
    local column = M.column_for(spec, tile)
    if column then
      out[column.order] = out[column.order] or {}
      local list = out[column.order]
      list[#list + 1] = tile
    end
  end
  return out
end

---Clamp a scroll index into a stack that may have shrunk (a window closed)
---or grown, so a closed window can never strand a column past its end.
---Empty stacks clamp to 0 (nothing to show).
---@param index integer?
---@param count integer
---@return integer
function M.clamp_scroll(index, count)
  if count <= 0 then
    return 0
  end
  index = index or 1
  if index < 1 then
    return 1
  end
  if index > count then
    return count
  end
  return index
end

---How much of the row each column gets. Declared `share`s are honoured like
---`hypr/scene/layout.lua`'s block shares; columns with no declared share
---split whatever is left evenly. One to three columns only — the desk is
---one row, never more (see docs/deck.md).
---@param columns Deck.Column[]
---@return number[] fraction per column, indexed like `columns`
local function fractions(columns)
  local declared, loose = 0, {}
  local out = {}
  for i, column in ipairs(columns) do
    if column.share then
      declared = declared + column.share
      out[i] = column.share
    else
      loose[#loose + 1] = i
    end
  end
  if #loose == 0 then
    if declared > 0 and math.abs(declared - 1) > 1e-9 then
      for i, value in ipairs(out) do
        out[i] = value / declared
      end
    end
    return out
  end
  local spare = math.max(1 - declared, 0)
  local each = spare / #loose
  for _, i in ipairs(loose) do
    out[i] = each
  end
  return out
end

---Place every column's members: the visible one at the column's ordinary
---geometry, every other member of the same column moved off-screen along
---the vertical axis — above the visible box for a member before the scroll
---index, below it for one after, so the direction of a scroll reads
---correctly once the compositor animates the move (LEO-402). A column
---always shows exactly one window at full column height — never a partial
---window, never a shrink-to-fit split (unlike a `scene` block's stack,
---which divides its share among every member). Scrolling changes which
---window is visible, not how much of it shows.
---@param spec Deck.Spec
---@param tiles Scene.Tile[] tiled windows on the deck workspace
---@param area Scene.Area
---@param opts { gaps_in: number?, gaps_out: Scene.CssGap?, scroll: table<integer, integer>? }
---gaps_out is sided the same way `layout.lua`'s `sides` reads it (LEO-421): a
---bare number applies to every side, a table names each one, with an unnamed
---side a real 0 -- deck no longer collapses it to one symmetric number.
---scroll: 1-based visible index per column order, from session state the
---provider owns; nil/missing defaults to 1 (the first window).
---@return Scene.Box[] boxes one per deck member, visible or off-screen
function M.boxes(spec, tiles, area, opts)
  opts = opts or {}
  local gaps_in = opts.gaps_in or 0
  local top, right, bottom, left = layout.sides(opts.gaps_out)
  local scroll = opts.scroll or {}

  local columns = {}
  for _, c in ipairs(spec.columns) do
    columns[#columns + 1] = c
  end
  table.sort(columns, function(a, b)
    return a.order < b.order
  end)
  -- The physical constraint (docs/deck.md): one row, one to three columns.
  -- A declaration outside that bound is truncated rather than refused here —
  -- validation belongs to the editor/loader, not this arithmetic.
  while #columns > MAX_COLUMNS do
    columns[#columns] = nil
  end

  local stacks = M.stacks(spec, tiles)
  local boxes = {}
  if #columns < MIN_COLUMNS then
    return boxes
  end

  local inner_x = area.x + left
  local inner_y = area.y + top
  local inner_w = area.w - left - right
  local inner_h = area.h - top - bottom
  local usable = inner_w - gaps_in * (#columns - 1)

  -- Where a hidden member of a column parks, one column-height off either
  -- edge — a fixed offset rather than one slot per hidden member, since
  -- nothing observes their relative order while off-screen; only the
  -- transition into/out of the visible slot is ever seen.
  local above_y = inner_y - inner_h - gaps_in
  local below_y = inner_y + inner_h + gaps_in

  local shares = fractions(columns)
  local cursor = inner_x
  for i, column in ipairs(columns) do
    local width = (i == #columns) and (inner_x + inner_w - cursor) or math.floor(usable * shares[i] + 0.5)
    local stack = stacks[column.order] or {}
    local representatives, members = layout.collapse_groups(stack)
    local index = M.clamp_scroll(scroll[column.order], #representatives)
    for j, rep in ipairs(representatives) do
      local y = (j == index) and inner_y or (j < index) and above_y or below_y
      local group_members = rep.group and members[rep.group]
      if group_members then
        for _, member in ipairs(group_members) do
          boxes[#boxes + 1] = { address = member.address, x = cursor, y = y, w = width, h = inner_h }
        end
      else
        boxes[#boxes + 1] = { address = rep.address, x = cursor, y = y, w = width, h = inner_h }
      end
    end
    cursor = cursor + width + gaps_in
  end
  return boxes
end

---Column order -> 1-based index of whichever representative is currently
---sitting at its column's visible geometry, derived from live window
---position rather than remembered scroll state (AGENTS.md "derive each
---pass"; docs/deck.md "Scroll survives a reload"). A config reload starts a
---fresh Lua state and wipes `deck_scroll`'s in-process table, but it does
---not move any window — whichever member was visible before the reload is
---still standing exactly where `M.boxes` last placed it, and every other
---member is still off-screen where it was. Reading that back is enough to
---recover the same visible member across a reload without persisting
---anything to the store.
---@param spec Deck.Spec
---@param tiles Scene.Tile[]
---@param area Scene.Area the same work area `M.boxes` was last called with
---@param positions table<string, HL.Box> live geometry per address (a
---member this pass has no position for is simply skipped)
---@return table<integer, integer> column order -> 1-based visible index
function M.live_scroll(spec, tiles, area, positions)
  local top, bottom = area.y, area.y + area.h
  local stacks = M.stacks(spec, tiles)
  local out = {}
  for order, stack in pairs(stacks) do
    local representatives = layout.collapse_groups(stack)
    for j, rep in ipairs(representatives) do
      local box = rep.address and positions[rep.address]
      -- `M.boxes` places exactly one representative per column inside the
      -- work area's vertical span; every other one sits a full column
      -- height above or below it, strictly outside. Whichever one lands
      -- inside is the visible member.
      if box and box.y >= top and box.y < bottom then
        out[order] = j
        break
      end
    end
  end
  return out
end

M.MIN_COLUMNS = MIN_COLUMNS
M.MAX_COLUMNS = MAX_COLUMNS

return M
