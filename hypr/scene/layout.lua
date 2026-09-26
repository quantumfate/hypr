-- Where the scene's windows go, as arithmetic.
--
-- Pure: a scene, the tiles present, and the work area go in; a box per tile
-- comes out. No `hl`, no dispatch, no timers. The provider that registers with
-- the compositor is a thin shell over this, which is what makes the
-- arrangement testable without a compositor at all.
--
-- This replaces a corrective loop that measured another layout's output and
-- dispatched fixes at it. The inversion removes, by construction: settle and
-- verify timers, geometry digests, turn budgets, the focus-dance (positioning
-- dispatchers act on the focused window, so every correction had to steal and
-- restore focus), and ordering via `movewindow` — which at a monitor edge moves
-- the window to the next monitor rather than reordering anything.
local spec_lib = require("hypr.scene.spec")

local M = {}

---The work area the compositor offered: the runtime's own HL.Box (the stub's
---LayoutContext.area type), so provider code needs no second geometry table.
---@alias Scene.Area HL.Box

---@class Scene.Tile
---@field address string
---@field class string
---@field tags string[]? Hyprland tags, for slot-block matching (LEO-364)
---@field group string? key shared by every member of one Hyprland group

---@class Scene.Box
---@field address string
---@field x number
---@field y number
---@field w number
---@field h number

---A group occupies one node in the layout however many windows it holds, so
---it is collapsed to one entry before anything is measured. Counting members
---individually is what used to make a lone Dofus group look like eight tiles
---and lose its framing.
---
---The members are kept alongside: slotting counts one, placing covers all of
---them, since every window in a group occupies its tile.
---`identity` names what a tile belongs to, when the live Hyprland group is
---not the answer. A deck passes the DECLARED identity (the block a window's
---tag names, `docs/declared-groups.md`): the compositor forms a group only
---once every member is on one workspace, and a strip that parks what it does
---not show parts a group out before it can form. Omitted, the live group is
---the identity, which is what the scene layout wants.
---@param tiles Scene.Tile[]
---@param identity fun(tile: Scene.Tile): string?|nil
---@return Scene.Tile[] representatives, table<string, Scene.Tile[]> members by identity
local function collapse_groups(tiles, identity)
  local seen, out, members = {}, {}, {}
  for _, tile in ipairs(tiles) do
    local key = identity and identity(tile) or tile.group
    if not key then
      out[#out + 1] = tile
    else
      members[key] = members[key] or {}
      local list = members[key]
      list[#list + 1] = tile
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = tile
      end
    end
  end
  return out, members
end

---Split the tiles into the scene's declared blocks and everything else,
---preserving each block's declared order and the strays' arrival order.
---@param scene Scene.Spec
---@param tiles Scene.Tile[]
---@return { block: Scene.Block?, tile: Scene.Tile }[]
local function sequence(scene, tiles)
  local by_block, strays = {}, {}
  for _, tile in ipairs(tiles) do
    local block = spec_lib.block_for(scene, tile.class, tile.tags)
    if block then
      by_block[block.order] = by_block[block.order] or { block = block, tiles = {} }
      local slot = by_block[block.order].tiles
      slot[#slot + 1] = tile
    else
      strays[#strays + 1] = tile
    end
  end

  local out = {}
  for _, block in ipairs(scene.blocks) do
    local entry = by_block[block.order]
    -- Every window of a block occupies the block's slot: a grouped block is
    -- one node (its members share one box, resolved in `boxes`); an ungrouped
    -- block's extra windows stack vertically within the same horizontal share
    -- rather than being dropped.
    if entry and entry.tiles[1] then
      out[#out + 1] = { block = block, tile = entry.tiles[1], tiles = entry.tiles }
    end
  end
  for _, tile in ipairs(strays) do
    out[#out + 1] = { block = nil, tile = tile, tiles = { tile } }
  end
  return out
end

-- Exposed so `hypr/lib/nav.lua` can compute the same left-to-right order for
-- keyboard navigation without re-deriving grouping/sequencing rules a second
-- time (and risking the two disagreeing about what "next tile" means).
M.collapse_groups = collapse_groups
M.sequence = sequence

---A stable identity for a sequenced entry, used by keyboard tile-swap
---(`hypr/scene/order.lua`) to name a slot without depending on which window
---happens to occupy it. A block's identity is its declared `order` (fixed by
---the scene document); a stray's is its own address (nothing else names it).
---@param entry { block: Scene.Block?, tile: Scene.Tile }
---@return string
function M.entry_key(entry)
  if entry.block then
    return "block:" .. tostring(entry.block.order)
  end
  return "stray:" .. tostring(entry.tile.address)
end

---Reorder sequenced entries to match a desired key order (see `entry_key`).
---Entries whose key is not named by `override` keep their original relative
---order, appended after the named ones — so a stale or partial override (a
---swapped tile that closed) degrades to the declared order instead of
---dropping anything.
---@param sequenced { block: Scene.Block?, tile: Scene.Tile }[]
---@param override string[]? desired key order
---@return { block: Scene.Block?, tile: Scene.Tile }[]
function M.reorder(sequenced, override)
  if not override or #override == 0 then
    return sequenced
  end
  local by_key, used = {}, {}
  for _, entry in ipairs(sequenced) do
    by_key[M.entry_key(entry)] = entry
  end
  local out = {}
  for _, key in ipairs(override) do
    local entry = by_key[key]
    if entry and not used[key] then
      out[#out + 1] = entry
      used[key] = true
    end
  end
  for _, entry in ipairs(sequenced) do
    if not used[M.entry_key(entry)] then
      out[#out + 1] = entry
    end
  end
  return out
end

---How much of the area each slot gets.
---
---Declared blocks keep their `share` of the area. Strays divide what is left,
---so the desk adjusts to what is present without the declaration having to
---predict it, and a block's ratio does not drift every time something
---unrelated opens. A block with no declared share is treated as a stray.
---@param slots table[]
---@return number[] fraction per slot, summing to 1
local function fractions(slots)
  local declared, loose = 0, {}
  local out = {}
  for i, slot in ipairs(slots) do
    local share = slot.block and slot.block.share
    if share then
      declared = declared + share
      out[i] = share
    else
      loose[#loose + 1] = i
    end
  end

  if #loose == 0 then
    -- Declared shares that do not sum to 1 are normalised rather than left to
    -- underfill: a scene with one block at 0.67 and nothing else should fill
    -- the panel, not leave a third of it empty.
    if declared > 0 and math.abs(declared - 1) > 1e-9 then
      for i, value in ipairs(out) do
        out[i] = value / declared
      end
    end
    return out
  end

  -- Strays never squeeze the declaration to nothing: if the declared shares
  -- already fill the area, everything is renormalised together instead.
  local spare = 1 - declared
  if spare <= 0 then
    local each = 1 / #slots
    for i = 1, #slots do
      out[i] = each
    end
    return out
  end
  local each = spare / #loose
  for _, i in ipairs(loose) do
    out[i] = each
  end
  return out
end

---A CssGap: either a single number applied to all four sides, or a table
---naming each side explicitly (Hyprland's own `general:gaps_out` shape).
---@alias Scene.CssGap number|{top: number?, right: number?, bottom: number?, left: number?}

---@class Scene.LayoutOpts
---@field gaps_in number gap between tiles
---@field gaps_out Scene.CssGap gap between the tiles and the screen edge; a
---table lets the top differ from the sides (the bar reserves its own height
---via layer-shell exclusive zone, so top must not also carry a full outer gap)
---@field solo_frame boolean? whether a lone tile is framed at all (default true)
---@field is_primary boolean? whether this is the scene's primary monitor
---(default true); the lone-tile centring never applies on a secondary one
---@field override string[]? desired left-to-right entry-key order
---(see `M.entry_key`, `M.reorder`); nil keeps the declared order

---A CssGap -> its four sides. A bare number applies to all of them.
---@param gaps Scene.CssGap?
---@return number top, number right, number bottom, number left
local function sides(gaps)
  if type(gaps) == "table" then
    return gaps.top or 0, gaps.right or 0, gaps.bottom or 0, gaps.left or 0
  end
  local n = tonumber(gaps) or 0
  return n, n, n, n
end
M.sides = sides

---The area left after a scene's outer gap is cut from the work area the
---compositor offered. This is `docs/scenes.md`'s "Areas" `work`: `area` is
---already the monitor less the bar's reserved strip (`ctx.area`), so cutting
---`gaps_out` here is the one remaining subtraction.
---@param area Scene.Area
---@param gaps_out Scene.CssGap?
---@return Scene.Box
function M.inner_area(area, gaps_out)
  local top, right, bottom, left = sides(gaps_out)
  return { x = area.x + left, y = area.y + top, w = area.w - left - right, h = area.h - top - bottom }
end

---The width fraction a lone slot would hold if every block the scene
---declares were on screen beside it — its "paired" width (LEO-421). Built
---from the scene's declaration alone, never the tiles actually present, so a
---companion that has not spawned yet still centres its sibling at the width
---they will eventually share.
---@param scene Scene.Spec
---@param slot { block: Scene.Block? }
---@return number
local function paired_fraction(scene, slot)
  local hypothetical, target_i = {}, nil
  for _, block in ipairs(scene.blocks) do
    hypothetical[#hypothetical + 1] = { block = block }
    if block == slot.block then
      target_i = #hypothetical
    end
  end
  -- A stray has no declared block of its own; give it one more slot beside
  -- the declared set, the same way `fractions` splits leftover share among
  -- strays already present.
  if not target_i then
    hypothetical[#hypothetical + 1] = {}
    target_i = #hypothetical
  end
  return fractions(hypothetical)[target_i] or 1
end

---Place every tile.
---
---@param scene Scene.Spec
---@param tiles Scene.Tile[] tiled windows on the scene's workspace
---@param area Scene.Area the work area the compositor offered
---@param opts Scene.LayoutOpts
---@return Scene.Box[] one box per tile, group members sharing their group's box
function M.boxes(scene, tiles, area, opts)
  opts = opts or {}
  local gaps_in = opts.gaps_in or 0
  local top, right, bottom, left = sides(opts.gaps_out)

  local representatives, members = collapse_groups(tiles)
  -- `strays = "float"` is no longer a layout concern (LEO-367): a floated
  -- stray is truly floated by the open-time executor
  -- (`hypr/scene/strays.lua` + `hypr/events/scene.lua`), and a floating
  -- window never reaches here as a tile (`hypr/scene/provider.lua` only
  -- offers `recalculate` the compositor's tiled targets). A stray still
  -- tiled for the moment between its open event and the dispatch landing
  -- gets the same `slot` treatment as a `strays = "slot"` scene, since it
  -- has not floated yet.
  local slots = M.reorder(sequence(scene, representatives), opts.override)
  if #slots == 0 then
    return {}
  end

  -- A lone tile is centred at the width it would have held with its
  -- declared partner present, rather than stretched to fill the panel. A
  -- group counts as one tile here, so the Dofus group alone on its
  -- workspace frames the same way. Never on a secondary monitor (LEO-421):
  -- there the scene has no ultrawide panel to compensate for, so a lone
  -- tile just takes the ordinary gaps.
  if #slots == 1 and opts.solo_frame ~= false and opts.is_primary ~= false then
    local base_w = area.w - left - right
    local paired_w = base_w * paired_fraction(scene, slots[1])
    local extra = math.max((base_w - paired_w) / 2, 0)
    left, right = left + extra, right + extra
  end

  local inner_x = area.x + left
  local inner_y = area.y + top
  local inner_w = area.w - left - right
  local inner_h = area.h - top - bottom
  local usable = inner_w - gaps_in * (#slots - 1)

  local out = {}
  local cursor = inner_x
  local shares = fractions(slots)
  for i, slot in ipairs(slots) do
    -- The last slot takes whatever remains, so rounding never leaves a seam
    -- against the right edge.
    local width = (i == #slots) and (inner_x + inner_w - cursor) or math.floor(usable * shares[i] + 0.5)
    if slot.tile.group and members[slot.tile.group] then
      -- Every window in a group occupies the group's tile, so they all take
      -- the same box; the compositor's groupbar is what distinguishes them.
      for _, tile in ipairs(members[slot.tile.group]) do
        out[#out + 1] = { address = tile.address, x = cursor, y = inner_y, w = width, h = inner_h }
      end
    elseif slot.block and not slot.block.group and #slot.tiles > 1 then
      -- An ungrouped block's extra windows stack vertically within its own
      -- share instead of being dropped: the declared share is the block's,
      -- not just its first window's.
      for _, box in ipairs(M.stack(slot.tiles, cursor, inner_y, width, inner_h, gaps_in)) do
        out[#out + 1] = box
      end
    else
      out[#out + 1] = { address = slot.tile.address, x = cursor, y = inner_y, w = width, h = inner_h }
    end
    cursor = cursor + width + gaps_in
  end
  return out
end

---Stack a block's windows vertically within one horizontal share: equal
---heights, `gaps_in` between them, the last one taking whatever rounding left.
---@param tiles Scene.Tile[]
---@param x number
---@param y number
---@param w number
---@param h number
---@param gaps_in number
---@return Scene.Box[]
function M.stack(tiles, x, y, w, h, gaps_in)
  local n = #tiles
  local usable_h = h - gaps_in * (n - 1)
  local out, cursor = {}, y
  for i, t in ipairs(tiles) do
    local height = (i == n) and (y + h - cursor) or math.floor(usable_h / n + 0.5)
    out[#out + 1] = { address = t.address, x = x, y = cursor, w = w, h = height }
    cursor = cursor + height + gaps_in
  end
  return out
end

---Whether a stray should float instead of staying tiled. Read by the open-time
---executor (`hypr/scene/strays.lua`), not by this layout any more (LEO-367):
---a floated window never reaches `boxes` as a tile in the first place.
---@param scene Scene.Spec
---@return boolean
function M.floats_strays(scene)
  return scene.strays == "float"
end

return M
