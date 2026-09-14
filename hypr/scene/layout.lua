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

-- Extra outer gap for a workspace holding a single tile, on top of whatever the
-- monitor profile gives it. Enough to read as deliberate on a 5120px panel
-- without stranding the window.
--
-- This is the whole of what an event layer used to do by rewriting a workspace
-- rule's `gaps_out` and restoring it later. Here it is a branch in the function
-- that already decides every box, so there is nothing to race.
local SOLO_EXTRA = 180

---@class Scene.Area
---@field x number
---@field y number
---@field w number
---@field h number

---@class Scene.Tile
---@field address string
---@field class string
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
---@param tiles Scene.Tile[]
---@return Scene.Tile[] representatives, table<string, Scene.Tile[]> members by group
local function collapse_groups(tiles)
  local seen, out, members = {}, {}, {}
  for _, tile in ipairs(tiles) do
    local key = tile.group
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
    local block = spec_lib.block_for(scene, tile.class)
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
    -- Only the block's first tile occupies a slot: a grouped block is one node,
    -- and an ungrouped block's extra windows stack behind the first rather than
    -- each claiming a share the declaration never promised them.
    if entry and entry.tiles[1] then
      out[#out + 1] = { block = block, tile = entry.tiles[1] }
    end
  end
  for _, tile in ipairs(strays) do
    out[#out + 1] = { block = nil, tile = tile }
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

---@class Scene.LayoutOpts
---@field gaps_in number gap between tiles
---@field gaps_out number gap between the tiles and the screen edge
---@field solo_extra number? extra outer gap for a lone tile (default SOLO_EXTRA)
---@field solo_frame boolean? whether a lone tile is framed at all (default true)

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
  local gaps_out = opts.gaps_out or 0

  local representatives, members = collapse_groups(tiles)
  local slots = sequence(scene, representatives)
  if #slots == 0 then
    return {}
  end

  -- A lone tile is framed rather than filling the panel. A group counts as one
  -- tile here, so the Dofus group alone on its workspace frames like a single
  -- window — which is the behaviour an event layer used to approximate.
  if #slots == 1 and opts.solo_frame ~= false then
    gaps_out = gaps_out + (opts.solo_extra or SOLO_EXTRA)
  end

  local inner_x = area.x + gaps_out
  local inner_y = area.y + gaps_out
  local inner_w = area.w - gaps_out * 2
  local inner_h = area.h - gaps_out * 2
  local usable = inner_w - gaps_in * (#slots - 1)

  local out = {}
  local cursor = inner_x
  local shares = fractions(slots)
  for i, slot in ipairs(slots) do
    -- The last slot takes whatever remains, so rounding never leaves a seam
    -- against the right edge.
    local width = (i == #slots) and (inner_x + inner_w - cursor) or math.floor(usable * shares[i] + 0.5)
    -- Every window in a group occupies the group's tile, so they all take the
    -- same box; the compositor's groupbar is what distinguishes them.
    local placed = slot.tile.group and members[slot.tile.group] or { slot.tile }
    for _, tile in ipairs(placed) do
      out[#out + 1] = { address = tile.address, x = cursor, y = inner_y, w = width, h = inner_h }
    end
    cursor = cursor + width + gaps_in
  end
  return out
end

---Whether a stray should float instead of taking a slot.
---
---Slotting is the default: the desk adjusts to what is present. A scene whose
---tile geometry is a fixed region — one being captured, where a box that moves
---when something unrelated opens invalidates the crop — opts out instead.
---@param scene Scene.Spec
---@return boolean
function M.floats_strays(scene)
  return scene.strays == "float"
end

return M
