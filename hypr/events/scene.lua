-- Window scene engine (LEO-245): drive window positioning from the scene.
--
-- A scene is a per-workspace arrangement of *blocks*. Each block names the
-- window classes it owns and the invariants that hold between those windows:
--
--   * `group` — every matching window lives in one Hyprland group, so the
--     block is a single tile however many windows it has;
--   * `order` — where the block's tile sits in the left-to-right sequence;
--   * `share` — the fraction of the work area the block's tile should hold.
--
-- The scene specs live in the host config next to `workspace_specs`
-- (hyprland.lua), keyed by the workspace's `default_name`.
--
-- Why a driver at all: Hyprland's positioning primitives act on the *focused*
-- window — the `window:` argument is ignored — and `moveintogroup` additionally
-- requires the target group to be adjacent on that axis (verified live, with a
-- real Dofus/zen scene, on the running build). There is no window-targeted
-- dispatch (this is exactly the finding LEO-214 recorded). So corrective
-- actions are a *focus-dance*: focus the window, dispatch, restore focus
-- (LEO-129). The loop converges because `window.resize` is exact on tiled
-- windows and adjacency is reachable in a bounded number of `movewindow` hops.
--
-- The driver reacts only to scene-window map/close. It never polls and never
-- fights a scene that already satisfies its blocks; every correction is
-- verified and stops at tolerance.

local hyg = require("hypr.lib.hypr")

-- How long after a window maps until its tiled geometry (`at`/`size`,
-- GEOMETRIC_GOAL) is final and directions/sizes can be aimed.
local SETTLE_MS = 100
-- Re-check the scene shortly after a corrective dispatch.
local VERIFY_MS = 80
-- Bounded `movewindow` hops to reach adjacency before giving up on a join.
local MAX_HOPS = 4
-- Bounded corrections per realize before stopping (a single join can take
-- several hops' worth of turns).
local MAX_TURNS = 8
-- A block that holds `share` +/- 2% of the work area is done.
local SHARE_TOL = 0.02

-- Scene state keyed by workspace `default_name`. Built once at require from
-- `config.host.workspaces.scenes`; the per-block membership sets are mutated
-- as windows fold in, so the scene is "that set", not whatever Hyprland
-- happens to be splitting.
---@class Scene
---@field ws_set table<string, true> matching workspace ids (as strings)
---@field blocks SceneBlock[]
---@field members table<integer, table<string, true>> membership per block order
---@field busy boolean a realize is in flight for this scene
---@class SceneBlock
---@field classes string[]
---@field group boolean
---@field order integer
---@field share number|nil
local scenes = {}

---@return boolean
local function is_special_workspace(spec_workspace)
  return tostring(spec_workspace):find("^special:")
end

---@param default_name string
---@return table<string, true>
local function ws_ids_for(default_name)
  local out = {}
  for _, spec in ipairs(config.host.workspaces.workspace_specs) do
    if not is_special_workspace(spec.workspace) and spec.default_name == default_name then
      out[tostring(spec.workspace)] = true
    end
  end
  return out
end

local function build()
  for _, spec in ipairs(config.host.workspaces.scenes or {}) do
    local blocks = {}
    for i, block in ipairs(spec.blocks) do
      blocks[i] = {
        classes = block.classes,
        group = block.group == true,
        order = block.order,
        share = block.share,
      }
    end
    table.sort(blocks, function(a, b)
      return a.order < b.order
    end)
    local members = {}
    for _, block in ipairs(blocks) do
      members[block.order] = {}
    end
    scenes[spec.default_name] = {
      ws_set = ws_ids_for(spec.default_name),
      blocks = blocks,
      members = members,
      busy = false,
    }
  end
end

---@param scene Scene
---@param w HL.Window
---@return boolean
local function on_scene(scene, w)
  local ws = w and w.workspace
  return ws ~= nil and scene.ws_set[tostring(ws.id)] ~= nil
end

---A class entry may be a plain literal ("Dofus.x64", "zen-gaming-media",
---"Kitty-Main") or a pattern ("Proj-[A-Za-z0-9_-]+") — the same dual meaning
---windowrules.lua gives class rules. Literals first, so hyphenated classes
---never trip on `-` being a Lua-pattern quantifier.
---@param w HL.Window
---@param patterns string[]
---@return boolean
local function class_matches(w, patterns)
  local cls = w and w.class
  if not cls then
    return false
  end
  for _, entry in ipairs(patterns) do
    if cls == entry or cls:match("^(" .. entry .. ")$") then
      return true
    end
  end
  return false
end

---@param scene Scene
---@param w HL.Window
---@return SceneBlock?
local function block_for(scene, w)
  for _, block in ipairs(scene.blocks) do
    if class_matches(w, block.classes) then
      return block
    end
  end
  return nil
end

---@return table<string, HL.Window>
local function live_map()
  local live = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    live[w.address] = w
  end
  return live
end

---HL.Group.members is a bare HL.Window when the group holds exactly one,
---otherwise an array — normalize to an array (same shape team.lua reads).
---@param group HL.Group?
---@return HL.Window[]
local function group_members(group)
  local members = group and group.members
  if not members then
    return {}
  end
  if members.title then
    return { members }
  end
  return members
end

---The live addresses of every window sharing `w`'s group.
---@param w HL.Window
---@param live table<string, HL.Window>
---@return table<string, true>
local function window_group_set(w, live)
  local out = {}
  for _, member in ipairs(group_members(w and w.group)) do
    if live[member.address] then
      out[member.address] = true
    end
  end
  return out
end

---@param a table<string, true>
---@param b table<string, true>
---@return boolean
local function sets_overlap(a, b)
  for address in pairs(a) do
    if b[address] then
      return true
    end
  end
  return false
end

---Fold `w`'s live group into the authoritative membership set (a group may
---carry dead members on close; those are dropped so the set never points at
---windows that are gone).
---@param w HL.Window
---@param members table<string, true>
---@param live table<string, HL.Window>
local function record_group(w, members, live)
  for _, member in ipairs(group_members(w and w.group)) do
    if live[member.address] then
      members[member.address] = true
    end
  end
end

---@param w HL.Window
---@return number, number window center
local function center(w)
  return w.at.x + w.size.x / 2, w.at.y + w.size.y / 2
end

---@param a HL.Window
---@param b HL.Window
---@return string "l"|"r"|"u"|"d" direction from a's center to b's center
local function direction_to(a, b)
  local ax, ay = center(a)
  local bx, by = center(b)
  local dx, dy = bx - ax, by - ay
  if math.abs(dx) >= math.abs(dy) then
    return dx >= 0 and "r" or "l"
  end
  return dy >= 0 and "d" or "u"
end

---@param a HL.Window
---@param b HL.Window
---@param dir string
---@return boolean whether b sits adjacent to a in `dir` (whether its edge
---touches a's, within a couple of pixels — "somewhere to the left" is not
---adjacent, mergeable is)
local function adjacent_in_direction(a, b, dir)
  local gap
  if dir == "r" then
    gap = b.at.x - (a.at.x + a.size.x)
  elseif dir == "l" then
    gap = a.at.x - (b.at.x + b.size.x)
  elseif dir == "d" then
    gap = b.at.y - (a.at.y + a.size.y)
  else
    gap = a.at.y - (b.at.y + b.size.y)
  end
  return gap >= -1 and gap <= 2
end

---@param target HL.Window
---@param live table<string, HL.Window>
---@param members table<string, true>
---@return HL.Window? the live group member nearest to `target`, if any
local function nearest_member(target, live, members)
  local nearest, nearest_sq = nil, nil
  for address in pairs(members) do
    local member = live[address]
    if member and member.at and member.size then
      local dx, dy = center(target)
      local mx, my = center(member)
      local dist = (mx - dx) * (mx - dx) + (my - dy) * (my - dy)
      if nearest_sq == nil or dist < nearest_sq then
        nearest, nearest_sq = member, dist
      end
    end
  end
  return nearest
end

---@param prev HL.Window?
---@param current_address string
local function restore_focus(prev, current_address)
  if prev and prev.address and prev.address ~= current_address then
    hl.dispatch(hl.dsp.focus({ window = "address:" .. prev.address }))
  end
end

---Fold `stray` into its block's authoritative group. The primitive takes a
---direction, not a target, and only reaches the window *beside* the group, so
---the stray hops toward the nearest member with `movewindow` until adjacent,
---then `moveintogroup` merges it. Focus is handed back when the fold settles
---or gives up (LEO-129). Completes via `cont(true)` when a merge was aimed,
---`cont(false)` when there was nothing to do (re-seed or dead end); the next
---realize turn re-checks membership either way.
---@param stray HL.Window
---@param members table<string, true>
---@param cont fun(aimed: boolean)
local function fold_stray(stray, members, cont)
  local prev = hl.get_active_window()
  local did_focus = false

  local function terminal()
    if did_focus then
      restore_focus(prev, stray.address)
    end
  end

  local function reseed()
    record_group(stray, members, live_map())
    terminal()
    cont(false)
  end

  local function attempt(hops)
    if hops > MAX_HOPS then
      terminal()
      cont(false)
      return
    end
    local live = live_map()
    local me = live[stray.address]
    if not me or not me.at or not me.size then
      terminal()
      cont(false)
      return
    end

    -- Already merged (the group tile absorbed it while we looked away).
    if sets_overlap(window_group_set(me, live), members) then
      record_group(me, members, live)
      terminal()
      cont(true)
      return
    end
    -- The authoritative set holds only dead addresses: this window is the new
    -- seed of the block's group.
    if not next(members) then
      reseed()
      return
    end

    local member = nearest_member(me, live, members)
    if not member then
      reseed()
      return
    end

    local dir = direction_to(me, member)
    if adjacent_in_direction(me, member, dir) then
      hl.dispatch(hl.dsp.focus({ window = "address:" .. me.address }))
      did_focus = true
      hl.dispatch(hl.dsp.window.move({ into_group = dir }))
      -- Fold the stray's address in immediately (its pre-merge group is
      -- itself); the verify step re-reads the merged group either way.
      record_group(me, members, live)
      terminal()
      cont(true)
      return
    end

    -- Hop one slot toward the member group and aim again once geometry settles.
    hl.dispatch(hl.dsp.focus({ window = "address:" .. me.address }))
    did_focus = true
    hl.dispatch(hl.dsp.window.move({ direction = dir }))
    hyg.oneshot(SETTLE_MS, function()
      attempt(hops + 1)
    end)
  end

  attempt(0)
end

---A live window sharing a group-block's group whose class is not the block's.
---@param scene Scene
---@param live table<string, HL.Window>
---@return HL.Window?, SceneBlock?
local function first_foreigner(scene, live)
  for _, block in ipairs(scene.blocks) do
    if block.group then
      local seen = {}
      for _, w in ipairs(hl.get_windows() or {}) do
        if not w.floating and w.address and on_scene(scene, w) and block_for(scene, w) == block then
          for _, member in ipairs(group_members(w.group)) do
            local other = live[member.address]
            if other and not seen[other.address] then
              seen[other.address] = true
              if not class_matches(other, block.classes) then
                return other, block
              end
            end
          end
        end
      end
    end
  end
  return nil, nil
end

---Focus `foreign` and move it out of the group; drop it from membership.
---@param foreign HL.Window
---@param members table<string, true>?
local function eject(foreign, members)
  if members then
    members[foreign.address] = nil
  end
  local prev = hl.get_active_window()
  hl.dispatch(hl.dsp.focus({ window = "address:" .. foreign.address }))
  hl.dispatch(hl.dsp.window.move({ direction = "r" }))
  restore_focus(prev, foreign.address)
end

---The first group-block window not yet folded into its authoritative set.
---@param scene Scene
---@param live table<string, HL.Window>
---@return HL.Window?, SceneBlock?
local function first_stray(scene, live)
  for _, block in ipairs(scene.blocks) do
    if block.group then
      local members = scene.members[block.order]
      for _, w in ipairs(hl.get_windows() or {}) do
        if not w.floating and w.address and w.at and w.size and on_scene(scene, w) and block_for(scene, w) == block then
          if not members[w.address] and not sets_overlap(window_group_set(w, live), members) then
            return w, block
          end
        end
      end
    end
  end
  return nil, nil
end

---The block's leftmost live tile.
---@param scene Scene
---@param block SceneBlock
---@return HL.Window?
local function first_tile(scene, block)
  local best
  for _, w in ipairs(hl.get_windows() or {}) do
    if not w.floating and w.at and w.size and on_scene(scene, w) and block_for(scene, w) == block then
      if not best or w.at.x < best.at.x then
        best = w
      end
    end
  end
  return best
end

---The blocks that have a live tile, in left-to-right geometry order.
---@param scene Scene
---@return SceneBlock[]
local function geometric_blocks(scene)
  local present = {}
  for _, block in ipairs(scene.blocks) do
    if first_tile(scene, block) then
      present[#present + 1] = block
    end
  end
  table.sort(present, function(a, b)
    local ta, tb = first_tile(scene, a), first_tile(scene, b)
    if ta.at.y ~= tb.at.y then
      return ta.at.y < tb.at.y
    end
    return ta.at.x < tb.at.x
  end)
  return present
end

---@param scene Scene
---@return { block: SceneBlock, dir: string }? first block out of order
local function wrong_order(scene)
  if #scene.blocks < 2 then
    return nil
  end
  local present = geometric_blocks(scene)
  local desired = {}
  for _, block in ipairs(scene.blocks) do
    for _, p in ipairs(present) do
      if p == block then
        desired[#desired + 1] = block
      end
    end
  end
  for i = 1, #present do
    if present[i] ~= desired[i] then
      local want = 0
      for j = 1, #desired do
        if desired[j] == present[i] then
          want = j
        end
      end
      return { block = present[i], dir = want > i and "r" or "l" }
    end
  end
  return nil
end

---@param scene Scene
---@return { block: SceneBlock, target: integer, tile: HL.Window }? under/over-sized block
local function wrong_share(scene)
  local tiles = {}
  for _, block in ipairs(scene.blocks) do
    if block.share then
      local tile = first_tile(scene, block)
      if tile then
        tiles[#tiles + 1] = tile
      end
    end
  end
  -- A single tile has nothing to share against; a 0.67 solo group must not
  -- shrink to two thirds of itself.
  if #tiles < 2 then
    return nil
  end
  local left, right = math.huge, -math.huge
  for _, tile in ipairs(tiles) do
    left = math.min(left, tile.at.x)
    right = math.max(right, tile.at.x + tile.size.x)
  end
  local span = right - left
  if span <= 0 then
    return nil
  end
  for _, block in ipairs(scene.blocks) do
    if block.share then
      local tile = first_tile(scene, block)
      local target = math.floor(block.share * span + 0.5)
      if math.abs(tile.size.x - target) > SHARE_TOL * span then
        return { block = block, target = target, tile = tile }
      end
    end
  end
  return nil
end

---Run one corrective action for the scene, then re-verify. A single action per
---turn — join is priority, then order, then share — keeps the geometry stable
---between dispatches, and the verify step makes the loop self-correcting:
---if a merge did not stick, the next turn sees a stray again and folds it with
---adjacency already in place (which is when `moveintogroup` actually works).
---@param scene Scene
local function realize(scene)
  if scene.busy then
    return
  end
  scene.busy = true
  local turns = 0

  local function step()
    turns = turns + 1
    if turns > MAX_TURNS then
      scene.busy = false
      return
    end

    local live = live_map()
    local foreign, foreign_block = first_foreigner(scene, live)
    if foreign then
      eject(foreign, foreign_block and scene.members[foreign_block.order])
      hyg.oneshot(VERIFY_MS, step)
      return
    end

    local stray, stray_block = first_stray(scene, live)
    if stray then
      fold_stray(stray, scene.members[stray_block.order], function()
        hyg.oneshot(VERIFY_MS, step)
      end)
      return
    end

    local order = wrong_order(scene)
    if order then
      local tile = first_tile(scene, order.block)
      local prev = hl.get_active_window()
      hl.dispatch(hl.dsp.focus({ window = "address:" .. tile.address }))
      hl.dispatch(hl.dsp.window.move({ direction = order.dir }))
      restore_focus(prev, tile.address)
      hyg.oneshot(VERIFY_MS, step)
      return
    end

    local share = wrong_share(scene)
    if share then
      local prev = hl.get_active_window()
      hl.dispatch(hl.dsp.focus({ window = "address:" .. share.tile.address }))
      hl.dispatch(hl.dsp.window.resize({ x = share.target, y = share.tile.size.y }))
      restore_focus(prev, share.tile.address)
      hyg.oneshot(VERIFY_MS, step)
      return
    end

    scene.busy = false
  end

  step()
end

---@param w HL.Window
---@return string? the scene whose scene window `w` is, if any
local function scene_for(w)
  for key, scene in pairs(scenes) do
    if on_scene(scene, w) and block_for(scene, w) then
      return key
    end
  end
  return nil
end

---@param key string
local function schedule_realize(key)
  hyg.oneshot(SETTLE_MS, function()
    realize(scenes[key])
  end)
end

build()

-- Seed: self-heal scenes already populated when the config reloads (the
-- re-registered handlers miss the windows that opened before this require).
for _, w in ipairs(hl.get_windows() or {}) do
  local key = scene_for(w)
  if key then
    schedule_realize(key)
  end
end

hl.on("window.open", function(w)
  local key = w and scene_for(w)
  if key then
    schedule_realize(key)
  end
end)

hl.on("window.close", function(w)
  local key = w and w.address and scene_for(w)
  if key then
    schedule_realize(key)
  end
end)

local M = {}

---Scene name owning this workspace, or nil.
---@param ws { id: integer|string }?
---@return string?
function M.active(ws)
  if not ws then
    return nil
  end
  local id = tostring(ws.id)
  for name, scene in pairs(scenes) do
    if scene.ws_set[id] then
      return name
    end
  end
  return nil
end

---Run the realize loop for the named scene.
---@param name string
function M.realize(name)
  local scene = scenes[name]
  if scene then
    realize(scene)
  end
end

---Leftmost live tile of the block matching `match`, or nil.
---@param name string
---@param match string|{ class: string }
---@return HL.Window?
function M.tile(name, match)
  local scene = scenes[name]
  local cls = type(match) == "table" and match.class or match
  if not scene or type(cls) ~= "string" then
    return nil
  end
  local block = block_for(scene, { class = cls })
  if not block then
    return nil
  end
  return first_tile(scene, block)
end

return M
