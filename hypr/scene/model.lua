-- What the scene wants next, as one intent (LEO-245).
--
-- Pure: a snapshot table and a spec go in, at most one intent comes out. No
-- `hl`, no timers, no dispatch. This is where the arrangement's decisions
-- live, so they can be read — and tested — without a compositor.
--
-- One intent per call, not a plan: every correction changes the geometry the
-- next decision depends on (a join collapses two tiles into one, a reorder
-- moves everything after it), so a batch computed up front would be acting on
-- a layout that no longer exists by the second step. The scheduler applies
-- one, waits for the compositor to settle, and asks again.
local spec_lib = require("hypr.scene.spec")

local M = {}

-- A block holding `share` +/- 2% of the tiled span is done. Below this the
-- resize is smaller than the animation it would trigger.
local SHARE_TOL = 0.02

---@class Scene.Win
---@field address string
---@field class string
---@field workspace string? workspace name
---@field workspace_id integer?
---@field floating boolean
---@field group string? stable key shared by every member of one Hyprland group
---@field x number
---@field y number
---@field w number
---@field h number

---@class Scene.Snapshot
---@field active string? name of the workspace the user is looking at
---@field windows Scene.Win[]

---@class Scene.Intent
---@field op "collect"|"evict"|"join"|"reorder"|"resize"
---@field address string the window the correction acts on
---@field key string identity of this correction, for the no-repeat rule
---@field workspace string? collect: where the window belongs
---@field target string? join: address of a window already in the destination group
---@field dir string? reorder: "l"|"r"
---@field width number? resize: target width in pixels

---The scene's own tiles: on its workspace, not floating, belonging to a block.
---`blocks` indexes a tile's block by address.
---@param spec Scene.Spec
---@param snap Scene.Snapshot
---@return Scene.Win[] tiles, table<string, Scene.Block> blocks
local function scene_tiles(spec, snap)
  local tiles, blocks = {}, {}
  for _, w in ipairs(snap.windows) do
    if w.workspace == spec.name and not w.floating then
      local block = spec_lib.block_for(spec, w.class)
      if block then
        tiles[#tiles + 1] = w
        blocks[w.address] = block
      end
    end
  end
  table.sort(tiles, function(a, b)
    return a.address < b.address
  end)
  return tiles, blocks
end

---Every tiled window on the scene's workspace, block member or not. The share
---denominator has to count these: a block that measured itself against only
---its siblings would aim at a fraction of a span that other windows are also
---occupying.
---@param spec Scene.Spec
---@param snap Scene.Snapshot
---@return Scene.Win[]
local function workspace_tiles(spec, snap)
  local out = {}
  for _, w in ipairs(snap.windows) do
    if w.workspace == spec.name and not w.floating then
      out[#out + 1] = w
    end
  end
  return out
end

---The block's leftmost (then topmost) tile.
---@param tiles Scene.Win[]
---@param blocks table<string, Scene.Block>
---@param block Scene.Block
---@return Scene.Win?
local function first_tile(tiles, blocks, block)
  local best
  for _, w in ipairs(tiles) do
    if blocks[w.address] == block then
      if not best or w.y < best.y or (w.y == best.y and w.x < best.x) then
        best = w
      end
    end
  end
  return best
end

---The group a block should converge on: whichever group already holds the
---most of the block's tiles, ties broken by address so the choice is stable
---across reads.
---
---Deriving this every pass — rather than holding a membership set — is what
---makes the engine recover from a split. Two groups can form for one block
---whenever `auto_group` wins a race at map time; a remembered set would treat
---one of them as authoritative forever and re-fight the other every event.
---The winning group is the one with the most of the block's tiles; `member`
---is one of its windows, so the caller has something to address. nil when the
---block holds no tiles.
---@param tiles Scene.Win[]
---@param blocks table<string, Scene.Block>
---@param block Scene.Block
---@return string? group, Scene.Win? member
local function dominant_group(tiles, blocks, block)
  local count, seed = {}, {}
  for _, w in ipairs(tiles) do
    if blocks[w.address] == block and w.group then
      count[w.group] = (count[w.group] or 0) + 1
      if not seed[w.group] or w.address < seed[w.group].address then
        seed[w.group] = w
      end
    end
  end
  local best, best_n
  for key, n in pairs(count) do
    if not best_n or n > best_n or (n == best_n and key < best) then
      best, best_n = key, n
    end
  end
  if best then
    return best, seed[best]
  end
  -- No member is grouped yet: the block's first tile is the seed the others
  -- fold into, under a key no live group can collide with (so `evict` finds
  -- nothing and `join` still has a destination to name).
  for _, w in ipairs(tiles) do
    if blocks[w.address] == block then
      return "solo:" .. w.address, w
    end
  end
  return nil, nil
end

---A member that wandered onto another real workspace, for a block that asked
---to collect. Only *owned* addresses qualify — a window is owned because it
---mapped into the scene, never because its class matches. Class-matching
---alone would make the scene claim every terminal on the desk.
---
---Dormant scenes collect nothing: if no member is home, the windows elsewhere
---are where the user is working, not debt.
---@param spec Scene.Spec
---@param snap Scene.Snapshot
---@param owned table<string, true>
---@param tiles Scene.Win[]
---@param blocks table<string, Scene.Block>
---@return Scene.Intent?
local function collect(spec, snap, owned, tiles, blocks)
  local home = {}
  for _, w in ipairs(tiles) do
    home[blocks[w.address]] = true
  end
  for _, w in ipairs(snap.windows) do
    local block = owned[w.address] and spec_lib.block_for(spec, w.class)
    if
      block
      and block.collect
      and home[block]
      and w.workspace ~= spec.name
      -- Real workspaces only: a member the user stashed on a special
      -- workspace (scratchpad, magic) is hidden on purpose, not adrift.
      and w.workspace_id
      and w.workspace_id >= 1
    then
      return { op = "collect", address = w.address, workspace = spec.name, key = "collect:" .. w.address }
    end
  end
  return nil
end

---A window that does not belong to the block sitting inside its group.
---`auto_group` can still swallow one despite the compiled `barred` rules —
---the rule only covers classes the scene knew to name.
---@param blocks table<string, Scene.Block>
---@param block Scene.Block
---@param group string
---@param snap Scene.Snapshot
---@return Scene.Intent?
local function evict(blocks, block, group, snap)
  for _, w in ipairs(snap.windows) do
    if w.group == group and blocks[w.address] ~= block then
      return { op = "evict", address = w.address, key = "evict:" .. w.address }
    end
  end
  return nil
end

---A block member that is not yet in the block's group.
---@param tiles Scene.Win[]
---@param blocks table<string, Scene.Block>
---@param block Scene.Block
---@param group string?
---@param seed Scene.Win?
---@return Scene.Intent?
local function join(tiles, blocks, block, group, seed)
  if not group or not seed then
    return nil
  end
  for _, w in ipairs(tiles) do
    if blocks[w.address] == block and w.group ~= group and w.address ~= seed.address then
      return {
        op = "join",
        address = w.address,
        target = seed.address,
        key = "join:" .. w.address .. ":" .. group,
      }
    end
  end
  return nil
end

---The first block whose tile sits out of the declared sequence, and which way
---it has to travel. Blocks with no tile are skipped: a scene is a sequence of
---whatever happens to be open, not a demand that everything be open.
---@param spec Scene.Spec
---@param tiles Scene.Win[]
---@param blocks table<string, Scene.Block>
---@return Scene.Intent?
local function reorder(spec, tiles, blocks)
  local present = {}
  for _, block in ipairs(spec.blocks) do
    local tile = first_tile(tiles, blocks, block)
    if tile then
      present[#present + 1] = { block = block, tile = tile }
    end
  end
  if #present < 2 then
    return nil
  end
  -- `present` is already in declared order; `geometric` is the same set as
  -- the screen has it. The first index where they disagree is the correction.
  local geometric = {}
  for i, entry in ipairs(present) do
    geometric[i] = entry
  end
  table.sort(geometric, function(a, b)
    if a.tile.y ~= b.tile.y then
      return a.tile.y < b.tile.y
    end
    return a.tile.x < b.tile.x
  end)
  for i = 1, #geometric do
    if geometric[i].block ~= present[i].block then
      local want
      for j = 1, #present do
        if present[j].block == geometric[i].block then
          want = j
        end
      end
      local dir = want > i and "r" or "l"
      return {
        op = "reorder",
        address = geometric[i].tile.address,
        dir = dir,
        key = "reorder:" .. geometric[i].tile.address .. ":" .. dir,
      }
    end
  end
  return nil
end

---A block whose tile is off its declared share of the workspace's tiled span.
---@param spec Scene.Spec
---@param snap Scene.Snapshot
---@param tiles Scene.Win[]
---@param blocks table<string, Scene.Block>
---@return Scene.Intent?
local function reshare(spec, snap, tiles, blocks)
  local all = workspace_tiles(spec, snap)
  -- A lone tile has nothing to share against: a 0.67 block alone on the
  -- workspace must not shrink to two thirds of itself.
  if #all < 2 then
    return nil
  end
  local left, right = math.huge, -math.huge
  for _, w in ipairs(all) do
    left = math.min(left, w.x)
    right = math.max(right, w.x + w.w)
  end
  local span = right - left
  if span <= 0 then
    return nil
  end
  for _, block in ipairs(spec.blocks) do
    local tile = block.share and first_tile(tiles, blocks, block)
    if tile then
      local target = math.floor(block.share * span + 0.5)
      if math.abs(tile.w - target) > SHARE_TOL * span then
        return {
          op = "resize",
          address = tile.address,
          width = target,
          key = "resize:" .. tile.address .. ":" .. target,
        }
      end
    end
  end
  return nil
end

---The scene's live geometry as a stable string. Two reads that agree mean the
---compositor has stopped moving: Hyprland animates every correction, and
---geometry measured mid-flight is how a converging loop turns into a dance.
---@param spec Scene.Spec
---@param snap Scene.Snapshot
---@return string
function M.digest(spec, snap)
  local parts = {}
  for _, w in ipairs(workspace_tiles(spec, snap)) do
    parts[#parts + 1] = ("%s:%s:%d,%d:%d,%d"):format(w.address, w.group or "-", w.x, w.y, w.w, w.h)
  end
  table.sort(parts)
  return table.concat(parts, ";")
end

---The single highest-priority correction the scene wants, or nil when it is
---already the arrangement it declares.
---
---Priority is causal, not cosmetic. Collection decides which windows are in
---play; eviction and joining decide how many tiles there are; only then can
---order and share mean anything, because both are measured in tiles.
---@param spec Scene.Spec
---@param snap Scene.Snapshot
---@param owned table<string, true> addresses this scene owns
---@return Scene.Intent?
function M.intent(spec, snap, owned)
  -- Corrections are only ever aimed at the workspace in front of the user.
  -- Reaching onto a hidden workspace means focusing a window there, which
  -- moves the user with it — and the resulting `workspace.active` arms the
  -- next scene, which focuses again. That loop is what made a workspace
  -- switch send the desk into a fit.
  if snap.active ~= spec.name then
    return nil
  end

  local tiles, blocks = scene_tiles(spec, snap)

  local intent = collect(spec, snap, owned or {}, tiles, blocks)
  if intent then
    return intent
  end

  for _, block in ipairs(spec.blocks) do
    if block.group then
      local group, seed = dominant_group(tiles, blocks, block)
      if group then
        intent = evict(blocks, block, group, snap) or join(tiles, blocks, block, group, seed)
        if intent then
          return intent
        end
      end
    end
  end

  return reorder(spec, tiles, blocks) or reshare(spec, snap, tiles, blocks)
end

return M
